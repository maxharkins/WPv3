function startScanMapping(hWP)
%STARTSCANMAPPING Robust playback of precomputed scan paths across tiles + Z levels.
% 19/02/2026 9:04
%
% Robustness features added:
%   - Handles single-tile or multi-tile stacks (scanPaths normalized to column)
%   - Skips empty tiles / missing Z-levels / missing paths gracefully
%   - Ensures each scan path has >= 2 points (prevents zero-length playback)
%   - Correct scan-time estimate consistent with playPreexistingPath resampling
%   - Resolves power from either hWP.Settings.Power_pct or Power_mW
%     (with Pockels calibration) and maps to PowerFrac robustly
%   - Safer Z motion with zfast: track Z in software, anchor-query at startup
%     and first layer of each tile, then move without per-layer queries
%   - (Optional) Finds X/Y galvo resources by name, with fallback to indices 118/119
%   - Checks Z-level quantization (0.01 µm) and warns/rounds to nearest step

    % ---- make sure isPaused and isCancelled are both false
    hWP.isCancelled = false;
    hWP.isPaused = false;

    % ---- time estimate for entire stack (your existing helper)
    figure
    [allTime_min, sliceTimes_min] = estimateScanMapTime(hWP);
    runLog = initRunLog(hWP, allTime_min, sliceTimes_min);

    fprintf('Started at: %s\n', timeofday(datetime('now')));
    fprintf('Expected end: %s\n', timeofday(datetime('now')) + minutes(allTime_min));

    try
        % ---- stack + stage
        stack     = hWP.hStacks;
        stagePath = hWP.aPath.Coordinates;

        scanPaths = stack.ScanPaths(:);    % normalize to column cell array
        numTiles  = numel(scanPaths);

        % ---- beam + galvos
        beam = hWP.hSI.hScan2D.hBeams{1};
        [hX, hY] = getXYGalvos(hWP);
        if isempty(hX) || isempty(hY)
            error('Could not acquire X/Y galvo handles.');
        end

        % ---- playback parameters
        PDT_s = hWP.Settings.PixelDwellTime_ms / 1000;   % seconds
        beamWaistDiameter_um = hWP.Settings.BeamWaistDiameter_um; % µm
        rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um);
        leadS = 0.004;
        tailS = 0.002;

        % Pull latest UI values directly when fields exist.
        if isprop(hWP, 'Power_Pct_Edit_Field')
            hWP.Settings.Power_pct = hWP.Power_Pct_Edit_Field.Value;
        elseif isprop(hWP, 'Power_Edit_Field')
            hWP.Settings.Power_pct = hWP.Power_Edit_Field.Value;
        end
        if isprop(hWP, 'Power_mW_Edit_Field')
            hWP.Settings.Power_mW = hWP.Power_mW_Edit_Field.Value;
        end

        % ---- power resolve (pct or objective-exit mW) -> power fraction
        [Pf, resolvedPct, resolvedObj_mW] = resolvePowerFraction(hWP.Settings);
        hWP.Settings.Power_pct = resolvedPct;
        hWP.Settings.Power_mW = resolvedObj_mW;
        if isprop(hWP, 'Power_Pct_Edit_Field')
            hWP.Power_Pct_Edit_Field.Value = resolvedPct;
        elseif isprop(hWP, 'Power_Edit_Field')
            hWP.Power_Edit_Field.Value = resolvedPct;
        end
        if isprop(hWP, 'Power_mW_Edit_Field') && isfinite(resolvedObj_mW)
            hWP.Power_mW_Edit_Field.Value = resolvedObj_mW;
        end

        % ---- Z constraints
        zStep_um          = 0.01;     % quantization step
        zMaxDeltaGuard   = 800;     % absolute guardrail (µm)
        zArriveTol_um    = 0.05;     % arrival tolerance (µm)
        zTrackResyncWarn_um = 0.2;    % warn when tracked-vs-queried Z drifts
        zMovePoll_s = 0.005;
        zMoveTimeout_s = 5;
        zAnchorEveryLayers = 5;       % periodic safety re-anchor cadence (0 disables)
        zAnchorDelta_um = 150;        % force anchor after large commanded Z step
        [scanPathFig, scanPathAx] = ensureScanPathAxes([], []);

        % ---- Z tracking + one-time startup safety anchor
        maskZOffset_um = hWP.hMask.Position(3);
        try
            waitZaxis_fast(hWP, 'PollInterval', zMovePoll_s, 'Timeout', zMoveTimeout_s);
            zTracked_um = getZaxis_fast(hWP, 'Frame', 'sample', 'Query', true);
            syncStageZState(hWP, zTracked_um);
        catch ME
            error('Failed to initialize Z safety anchor: %s', ME.message);
        end

        [zFirstTarget_um, hasFirstTarget] = findFirstExecutableZTarget(scanPaths, stack, zStep_um, hWP.Settings.ZTraversalMode, maskZOffset_um);
        if hasFirstTarget
            startupDelta = abs(zTracked_um - zFirstTarget_um);
            if startupDelta >= zMaxDeltaGuard
                warning('Refusing startup: current %.2f µm, first target %.2f µm (Δ=%.2f µm)', ...
                    zTracked_um, zFirstTarget_um, startupDelta);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.status = "aborted_guardrail";
                runLog.layers(end+1) = buildLayerRecord(0, 0, NaN, zFirstTarget_um, 0, NaN, 0, "z_guardrail_abort_startup", "Exceeded startup Z delta guard.", startupDelta); %#ok<AGROW>
                runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                finalizeRunLog(hWP, runLog);
                return;
            end
        end

    % ============================================================
    % TILE LOOP
    % ============================================================
        for tileIdx = 1:numTiles

        % ---- skip empty tile
        if tileIdx > numel(scanPaths) || isempty(scanPaths{tileIdx})
            fprintf('Tile %d empty, skipping.\n', tileIdx);
            continue;
        end

        % ---- move stage to tile
        try
            goToStagePath(hWP, stagePath, tileIdx);
            while hWP.hSI.hMotors.moveInProgress
                pause(0.05);
            end
        catch ME
            warning('Stage move failed for Tile %d: %s', tileIdx, ME.message);
            runLog.events(end+1) = buildEvent('stage_move_failed', tileIdx, 0, ME.message); %#ok<AGROW>
            continue;
        end

        % ---- Z levels for this tile
        if ~isprop(stack,'ArbitraryZs') || tileIdx > numel(stack.ArbitraryZs)
            fprintf('Tile %d has no Z levels.\n', tileIdx);
            continue;
        end

        zLevels = stack.ArbitraryZs{tileIdx}(:);
        if isempty(zLevels)
            fprintf('Tile %d has no Z levels.\n', tileIdx);
            continue;
        end

        % ---- quantize Z
        zQ = round(zLevels / zStep_um) * zStep_um;
        if any(abs(zQ - zLevels) > 1e-9)
            warning('Tile %d: rounding Z to %.3f µm grid.', tileIdx, zStep_um);
        end
        zLevels = zQ;

        % ---- scan paths for this tile
        tilePaths = scanPaths{tileIdx};
        if isrow(tilePaths), tilePaths = tilePaths.'; end

        % ---- enforce alignment
        n = min(numel(tilePaths), numel(zLevels));
        tilePaths = tilePaths(1:n);
        zLevels   = zLevels(1:n);

        % ---- Z traversal order
        switch hWP.Settings.ZTraversalMode
            case "ascending"
                [zLevels, order] = sort(zLevels, 'ascend');
            case "descending"
                [zLevels, order] = sort(zLevels, 'descend');
            otherwise
                error('Invalid ZTraversalMode.');
        end
        tilePaths = tilePaths(order);
        firstLayerIdx = find(~cellfun(@isempty, tilePaths), 1, 'first');
        layersSinceAnchor = 0;
        if ~isempty(firstLayerIdx)
            zFirstTileWorld = zLevels(firstLayerIdx) + maskZOffset_um;
            try
                zAnchor_um = getZaxis_fast(hWP, 'Frame', 'sample', 'Query', true);
            catch ME
                warning('Tile %d first-layer safety query failed: %s', tileIdx, ME.message);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.status = "aborted_z_safety";
                runLog.layers(end+1) = buildLayerRecord(tileIdx, firstLayerIdx, zLevels(firstLayerIdx), zFirstTileWorld, 0, NaN, 0, "z_safety_query_failed", string(ME.message)); %#ok<AGROW>
                runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                finalizeRunLog(hWP, runLog);
                return;
            end

            drift = abs(zAnchor_um - zTracked_um);
            if drift > zTrackResyncWarn_um
                warning('Tile %d: re-anchoring tracked Z by %.3f µm (tracked %.3f, queried %.3f).', ...
                    tileIdx, drift, zTracked_um, zAnchor_um);
                runLog.events(end+1) = buildEvent('z_track_resync', tileIdx, firstLayerIdx, ...
                    sprintf('Resynced tracked Z by %.3f um (tracked %.3f -> queried %.3f).', drift, zTracked_um, zAnchor_um)); %#ok<AGROW>
            end
            zTracked_um = zAnchor_um;
            syncStageZState(hWP, zTracked_um);
            layersSinceAnchor = 0;

            zDeltaFirst = abs(zTracked_um - zFirstTileWorld);
            if zDeltaFirst >= zMaxDeltaGuard
                warning('Refusing Z move (tile %d first layer): current %.2f µm, target %.2f µm (Δ=%.2f µm)', ...
                    tileIdx, zTracked_um, zFirstTileWorld, zDeltaFirst);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.status = "aborted_guardrail";
                runLog.layers(end+1) = buildLayerRecord(tileIdx, firstLayerIdx, zLevels(firstLayerIdx), zFirstTileWorld, 0, NaN, 0, "z_guardrail_abort_first_layer", "Exceeded first-layer Z delta guard.", zDeltaFirst); %#ok<AGROW>
                runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                finalizeRunLog(hWP, runLog);
                return;
            end
        end

        % ========================================================
        % Z LOOP
        % ========================================================
            for zIdx = 1:numel(zLevels)
            runLog.counts.layersAttempted = runLog.counts.layersAttempted + 1;

            if isempty(tilePaths{zIdx})
                runLog.counts.layersSkipped = runLog.counts.layersSkipped + 1;
                runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLevels(zIdx), NaN, 0, NaN, 0, "empty_path", ""); %#ok<AGROW>
                continue;
            end

            zLocal = zLevels(zIdx);

            zWorld = zLocal + maskZOffset_um;
            zDelta = abs(zTracked_um - zWorld);

            
            % ---- guardrail
            if zDelta >= zMaxDeltaGuard
                warning('Refusing Z move: current %.2f µm, target %.2f µm (Δ=%.2f µm)', ...
                        zTracked_um, zWorld, zDelta);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.status = "aborted_guardrail";
                runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, 0, NaN, 0, "z_guardrail_abort", "Exceeded Z delta guard.", zDelta); %#ok<AGROW>
                runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                finalizeRunLog(hWP, runLog);
                return;
            end

            % ---- move Z
            moveErr = "";
            moveStart = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            tic
            try
                hWP.hSI.hMotors.moveSampleZ(zWorld,true)
                % outZ = moveZaxis_fast(hWP, zWorld, ...
                %     'Type', 'absolute', ...
                %     'Frame', 'sample', ...
                %     'QueryBefore', false, ...
                %     'QueryAfter', false, ...
                %     'Blocking', true, ...
                %     'PollInterval', zMovePoll_s, ...
                %     'Timeout', zMoveTimeout_s);
                syncStageZState(hWP, zWorld);
            catch ME
                warning('Z move failed (Tile %d Z %d): %s', tileIdx, zIdx, ME.message);
                moveErr = string(ME.message);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, 0, NaN, 0, "z_move_failed", moveErr, zDelta, moveStart, string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'))); %#ok<AGROW>
                continue;
            end
            moveElapsed = toc;

            layersSinceAnchor = layersSinceAnchor + 1;
            doAnchor = false;
            anchorReason = "periodic";
            if ~isempty(firstLayerIdx) && zIdx == firstLayerIdx
                doAnchor = true;
                anchorReason = "first_layer";
            elseif zAnchorEveryLayers > 0 && layersSinceAnchor >= zAnchorEveryLayers
                doAnchor = true;
                anchorReason = "periodic";
            elseif zDelta >= zAnchorDelta_um
                doAnchor = true;
                anchorReason = "large_step";
            end

            if doAnchor
                try
                    zAnchorAfter_um = getZaxis_fast(hWP, 'Frame', 'sample', 'Query', true);
                    zArrivalErr = abs(zAnchorAfter_um - zWorld);
                    zTracked_um = zAnchorAfter_um;
                    syncStageZState(hWP, zTracked_um);
                    layersSinceAnchor = 0;
                    if zArrivalErr > zArriveTol_um
                        warning('Tile %d Z %d arrival off (%s): got %.3f µm, wanted %.3f µm', ...
                            tileIdx, zIdx, anchorReason, zAnchorAfter_um, zWorld);
                        runLog.events(end+1) = buildEvent('z_arrival_offset', tileIdx, zIdx, ...
                            sprintf('Arrival error %.3f um (reason=%s, got %.3f, wanted %.3f).', ...
                            zArrivalErr, anchorReason, zAnchorAfter_um, zWorld)); %#ok<AGROW>
                    end
                catch ME
                    warning('Tile %d Z %d anchor query failed (%s): %s', tileIdx, zIdx, anchorReason, ME.message);
                    runLog.events(end+1) = buildEvent('z_arrival_query_failed', tileIdx, zIdx, ME.message); %#ok<AGROW>
                end
            end

            % ---- XY path (translate AFTER Z success)
            scanPathXY = tilePaths{zIdx};
            scanPathXY = unique(scanPathXY, 'rows', 'stable');

            if size(scanPathXY,1) < 2
                fprintf('Tile %d Z %d: path too short, skipping.\n', tileIdx, zIdx);
                runLog.counts.layersSkipped = runLog.counts.layersSkipped + 1;
                runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, size(scanPathXY,1), NaN, 0, "path_too_short", "Path had fewer than two points.", zDelta); %#ok<AGROW>
                continue;
            end
           
            scanPathXY = rmmissing(scanPathXY,1); % remove NaN
            
            x_um = scanPathXY(:,1);
            y_um = scanPathXY(:,2);

            % ---- bounds safety
            assert(all(abs(x_um)<=500 & abs(y_um)<=500), ...
                'Path exceeds ±500 µm bounds.');

            % ---- live XY path (replace previous Z layer plot)
            [scanPathFig, scanPathAx] = ensureScanPathAxes(scanPathFig, scanPathAx);
            cla(scanPathAx);
            plot(scanPathAx, x_um, y_um);
            title(scanPathAx, 'ScanPath');
            xlabel(scanPathAx, 'x (µm)');
            ylabel(scanPathAx, 'y (µm)');
            xlim(scanPathAx, [-500 500]);
            ylim(scanPathAx, [-500 500]);
            drawnow;

            % ---- time estimate
            totalLength_um = sum(hypot(diff(x_um), diff(y_um)));
            estimatedTime_s = (totalLength_um / rasterSpacing_um) * PDT_s + leadS + tailS;

            fprintf('Tile %d Z %d   | Z=%.2f µm | %.3f s\n', ...
                    tileIdx, zIdx, zWorld, estimatedTime_s);

            % ---- execute scan
            scanStart = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            status = "completed";
            errMsg = moveErr;
            try
                playPreexistingPath(hX, hY, x_um, y_um, PDT_s, ...
                    'BeamWaistDiameter_um', beamWaistDiameter_um, ...
                    'BeamHandle', beam, ...
                    'PowerFrac', Pf, ...
                    'StartHold_s', leadS, ...
                    'EndHold_s', tailS, ...
                    'ParkWhenDone', false);
            catch ME
                warning('Scan failed (Tile %d Z %d): %s', tileIdx, zIdx, ME.message);
                status = "scan_failed";
                errMsg = string(ME.message);
                runLog.counts.layersFailed = runLog.counts.layersFailed + 1;
                runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, size(scanPathXY,1), totalLength_um, estimatedTime_s, status, errMsg, zDelta, scanStart, string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS')), moveElapsed); %#ok<AGROW>
                continue;
            end
            scanEnd = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
            runLog.counts.layersCompleted = runLog.counts.layersCompleted + 1;
            runLog.layers(end+1) = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, size(scanPathXY,1), totalLength_um, estimatedTime_s, status, errMsg, zDelta, scanStart, scanEnd, moveElapsed); %#ok<AGROW>
            
            drawnow % make sure pause updates

            % ---- PAUSE HERE (safe boundary)
            waitIfPaused(hWP);
            
            % ---- optional cancel check (future)
            if isprop(hWP,'isCancelled') && hWP.isCancelled
                warning('Scan cancelled by user.');
                runLog.status = "cancelled";
                runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                finalizeRunLog(hWP, runLog);
                return;
            end

            % % ---- progress UI
            % try
            %     updateTimeProgressBar(hWP, tileIdx, zIdx, allTime_min, sliceTimes_min);
            % catch
            % end
            end
        end % Double counting tranlated positions with .txt files (at least known for scanpaths on Feb 22, 2026)
        runLog.status = "completed";
        runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
        finalizeRunLog(hWP, runLog);
    catch ME
        runLog.status = "error";
        runLog.events(end+1) = buildEvent('fatal_error', 0, 0, ME.message); %#ok<AGROW>
        runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
        finalizeRunLog(hWP, runLog);
        rethrow(ME);
    end
end


% -------------------------------------------------------------------------
function [zWorld, tf] = findFirstExecutableZTarget(scanPaths, stack, zStep_um, zTraversalMode, maskZOffset_um)
    zWorld = NaN;
    tf = false;

    for tileIdx = 1:numel(scanPaths)
        tilePaths = scanPaths{tileIdx};
        if isempty(tilePaths)
            continue;
        end
        if isrow(tilePaths), tilePaths = tilePaths.'; end

        if ~isprop(stack, 'ArbitraryZs') || tileIdx > numel(stack.ArbitraryZs) || isempty(stack.ArbitraryZs{tileIdx})
            continue;
        end
        zLevels = stack.ArbitraryZs{tileIdx}(:);
        if isempty(zLevels)
            continue;
        end

        zLevels = round(zLevels / zStep_um) * zStep_um;
        n = min(numel(tilePaths), numel(zLevels));
        if n == 0
            continue;
        end
        tilePaths = tilePaths(1:n);
        zLevels = zLevels(1:n);

        switch zTraversalMode
            case "ascending"
                [zLevels, order] = sort(zLevels, 'ascend');
            case "descending"
                [zLevels, order] = sort(zLevels, 'descend');
            otherwise
                error('Invalid ZTraversalMode.');
        end
        tilePaths = tilePaths(order);

        firstIdx = find(~cellfun(@isempty, tilePaths), 1, 'first');
        if isempty(firstIdx)
            continue;
        end

        zWorld = zLevels(firstIdx) + maskZOffset_um;
        tf = true;
        return;
    end
end

% -------------------------------------------------------------------------
function [hX, hY] = getXYGalvos(hWP)
%GETXYGALVOS Try name-based lookup, then fallback indices 118/119.

    hX = [];
    hY = [];

    % Attempt name-based search in resource store (preferred)
    try
        rs = hWP.hSI.hResourceStore.hResources;
        for k = 1:numel(rs)
            r = rs{k};
            if isempty(r) || ~isobject(r), continue; end

            % Many ScanImage resources have a "name" property
            nm = '';
            try nm = string(r.name); catch, end

            if contains(lower(nm), "x galvo")
                hX = r;
            elseif contains(lower(nm), "y galvo")
                hY = r;
            end
        end
    catch
        % ignore and fall back below
    end

    % Fallback to your known indices if needed
    if isempty(hX) || isempty(hY)
        try
            rs = hWP.hSI.hResourceStore.hResources;
            if isempty(hX) && numel(rs) >= 118, hX = rs{118}; end
            if isempty(hY) && numel(rs) >= 119, hY = rs{119}; end
        catch
        end
    end
end

function waitIfPaused(app)
% waitIfPaused  Yield to UI while paused, without blocking ScanImage
    didWarn = false;
    while app.isPaused
        if didWarn == false
            warning('Scan paused by user...')
            didWarn = true;
        end
        drawnow;      % allows Pause/Resume/Cancel callbacks to run
        pause(0.05);  % light throttle, not a hard block
    end
end

function runLog = initRunLog(hWP, allTime_min, sliceTimes_min)
    startedAt = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS');
    runId = sprintf('scanrun_%s', datestr(startedAt, 'yyyymmdd_HHMMSS'));

    imported = struct('path', '', 'label', '');
    try
        if isappdata(hWP.UIFigure, 'WPImportedFilePath')
            imported.path = getappdata(hWP.UIFigure, 'WPImportedFilePath');
        end
        if isappdata(hWP.UIFigure, 'WPImportedFileLabel')
            imported.label = getappdata(hWP.UIFigure, 'WPImportedFileLabel');
        end
    catch
    end

    stackSummary = struct('numTiles', 0, 'zLayersPerTile', [], 'pointsPerTile', []);
    try
        scanPaths = hWP.hStacks.ScanPaths;
        stackSummary.numTiles = numel(scanPaths);
        zLayers = zeros(numel(scanPaths), 1);
        pts = zeros(numel(scanPaths), 1);
        for t = 1:numel(scanPaths)
            tile = scanPaths{t};
            if isempty(tile), continue; end
            zLayers(t) = numel(tile);
            for z = 1:numel(tile)
                if ~isempty(tile{z})
                    pts(t) = pts(t) + size(tile{z}, 1);
                end
            end
        end
        stackSummary.zLayersPerTile = zLayers;
        stackSummary.pointsPerTile = pts;
    catch
    end

    runLog = struct();
    runLog.runId = runId;
    runLog.status = "running";
    runLog.startedAt_local = char(startedAt);
    runLog.endedAt_local = '';
    runLog.duration_s = NaN;
    runLog.host = char(getenv('COMPUTERNAME'));
    if isempty(runLog.host)
        runLog.host = char(getenv('HOSTNAME'));
    end
    runLog.matlabVersion = version;
    runLog.estimatedTotalTime_min = allTime_min;
    runLog.estimatedSliceTimes_min = sliceTimes_min;
    runLog.settings = safeStruct(hWP.Settings);
    runLog.maskPosition_um = safeGetMaskPos(hWP);
    runLog.stagePath_um = safeGetStagePath(hWP);
    runLog.arbitraryZs_um = safeGetArbitraryZs(hWP);
    runLog.stackSummary = stackSummary;
    runLog.importedFile = imported;
    runLog.layers = repmat(buildLayerRecord(0,0,NaN,NaN,0,NaN,NaN,"","",""), 0, 1);
    runLog.events = repmat(buildEvent("init",0,0,""), 0, 1);
    runLog.counts = struct('tilesTotal', stackSummary.numTiles, 'layersAttempted', 0, ...
                           'layersCompleted', 0, 'layersSkipped', 0, 'layersFailed', 0);
end

function rec = buildLayerRecord(tileIdx, zIdx, zLocal, zWorld, nPts, pathLen, estTime, status, errMsg, zDelta, startStr, endStr, moveElapsed)
    if nargin < 10, zDelta = NaN; end
    if nargin < 11 || isempty(startStr), startStr = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS')); end
    if nargin < 12 || isempty(endStr), endStr = startStr; end
    if nargin < 13, moveElapsed = NaN; end

    rec = struct();
    rec.tileIdx = tileIdx;
    rec.zIdx = zIdx;
    rec.zLocal_um = zLocal;
    rec.zWorld_um = zWorld;
    rec.pathPointCount = nPts;
    rec.pathLength_um = pathLen;
    rec.estimatedTime_s = estTime;
    rec.status = char(status);
    rec.error = char(errMsg);
    rec.zMoveDelta_um = zDelta;
    rec.zMoveTime_s = moveElapsed;
    rec.startedAt_local = char(startStr);
    rec.endedAt_local = char(endStr);
end

function evt = buildEvent(kind, tileIdx, zIdx, message)
    evt = struct();
    evt.time_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    evt.kind = char(kind);
    evt.tileIdx = tileIdx;
    evt.zIdx = zIdx;
    evt.message = char(message);
end

function s = safeStruct(v)
    if isstruct(v)
        s = v;
    else
        s = struct();
    end
end

function p = safeGetMaskPos(hWP)
    p = [NaN NaN NaN];
    try
        p = hWP.hMask.Position;
    catch
    end
end

function syncStageZState(hWP, z_um)
    try
        if ~isprop(hWP, 'hStage') || isempty(hWP.hStage)
            return;
        end
        pos = hWP.hStage.Position;
        if isnumeric(pos) && numel(pos) >= 3 && isfinite(z_um)
            pos(3) = double(z_um);
            hWP.hStage.Position = pos;
        end
    catch
        % Non-fatal for scan execution.
    end
end

function [fig, ax] = ensureScanPathAxes(fig, ax)
    if nargin < 1 || isempty(fig) || ~isgraphics(fig) || ...
       nargin < 2 || isempty(ax) || ~isgraphics(ax, 'axes')
        fig = figure('Name', 'ScanPath', 'NumberTitle', 'off');
        ax = axes(fig);
    end
    title(ax, 'ScanPath');
    xlabel(ax, 'x (µm)');
    ylabel(ax, 'y (µm)');
    xlim(ax, [-500 500]);
    ylim(ax, [-500 500]);
end

function p = safeGetStagePath(hWP)
    p = [];
    try
        p = hWP.aPath.Coordinates;
    catch
    end
end

function z = safeGetArbitraryZs(hWP)
    z = {};
    try
        z = hWP.hStacks.ArbitraryZs;
    catch
    end
end

function [powerFrac, resolvedPct, resolvedObj_mW] = resolvePowerFraction(settings)
    pct = getSettingScalar(settings, 'Power_pct', NaN);
    obj_mW = getSettingScalar(settings, 'Power_mW', NaN);

    hasPct = isfinite(pct);
    hasObj = isfinite(obj_mW);

    if hasObj
        if ~isfield(settings, 'PockelsCalibration') || ~isstruct(settings.PockelsCalibration) || isempty(fieldnames(settings.PockelsCalibration))
            error('Power_mW requested but Settings.PockelsCalibration is missing. Run pockelsCellPowerCalibration first.');
        end
        pct = objectivePower_mWToPercent(settings.PockelsCalibration, obj_mW);
        hasPct = true;
    end

    if ~hasPct
        error('Neither Settings.Power_pct nor calibrated Settings.Power_mW is available.');
    end

    resolvedPct = max(0, min(100, double(pct)));
    powerFrac = resolvedPct / 100;

    if hasObj
        resolvedObj_mW = double(obj_mW);
    else
        resolvedObj_mW = percentToObjectivePower_mW(settings, resolvedPct);
    end
end

function mW = percentToObjectivePower_mW(settings, pct)
    mW = NaN;
    if ~isfield(settings, 'PockelsCalibration') || ~isstruct(settings.PockelsCalibration)
        return;
    end
    c = settings.PockelsCalibration;
    try
        if isfield(c, 'percentToPowerObjective_mW') && isa(c.percentToPowerObjective_mW, 'function_handle')
            mW = double(c.percentToPowerObjective_mW(pct));
            return;
        end
        if isfield(c, 'A') && isfield(c, 'omega') && isfield(c, 'phi') && isfield(c, 'D') && isfield(c, 'powerEfficiency')
            powerW = c.A .* sin(c.omega .* pct + c.phi) + c.D;
            mW = double((powerW ./ c.powerEfficiency) * 1e3);
        end
    catch
        mW = NaN;
    end
end

function pct = objectivePower_mWToPercent(cal, obj_mW)
    obj_W = obj_mW / 1e3;
    if isfield(cal, 'powerObjective_WToPercent') && isa(cal.powerObjective_WToPercent, 'function_handle')
        pct = double(cal.powerObjective_WToPercent(obj_W));
        return;
    end
    if isfield(cal, 'objectivePowerToPCPower') && isa(cal.objectivePowerToPCPower, 'function_handle') && ...
       isfield(cal, 'powerToPercent') && isa(cal.powerToPercent, 'function_handle')
        pcW = cal.objectivePowerToPCPower(obj_W);
        pct = double(cal.powerToPercent(pcW));
        return;
    end
    req = {'A','omega','phi','D','powerEfficiency'};
    for i = 1:numel(req)
        if ~isfield(cal, req{i})
            error('PockelsCalibration is missing "%s".', req{i});
        end
    end
    pcW = obj_W * cal.powerEfficiency;
    pct = powerToPercentFromParams(pcW, cal.A, cal.omega, cal.phi, cal.D);
end

function val = getSettingScalar(settings, fieldName, fallback)
    val = fallback;
    if isstruct(settings) && isfield(settings, fieldName)
        v = settings.(fieldName);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            val = double(v);
        end
    end
end

function percent = powerToPercentFromParams(power, A, omega, phi, D)
    if abs(A) < eps
        error('Calibration amplitude is too small; inversion is ill-defined.');
    end
    if abs(omega) < eps
        error('Calibration omega is too small; inversion is ill-defined.');
    end

    Pmin = D - abs(A);
    Pmax = D + abs(A);
    tol = 1e-9;
    if any(power < (Pmin - tol) | power > (Pmax + tol))
        error('Requested power outside calibrated downstream range [%.6g, %.6g] W.', Pmin, Pmax);
    end

    power = power(:);
    percent = zeros(size(power));
    period = abs(2 * pi / omega);

    for i = 1:numel(power)
        s = (power(i) - D) / A;
        s = min(max(s, -1), 1);
        alpha = asin(s);

        b1 = (alpha - phi) / omega;
        b2 = (pi - alpha - phi) / omega;

        nMin = floor((0 - max([b1 b2])) / period) - 1;
        nMax = ceil((100 - min([b1 b2])) / period) + 1;
        k = nMin:nMax;

        candidates = [b1 + k * period, b2 + k * period];
        inRange = candidates >= 0 & candidates <= 100;
        candidates = candidates(inRange);

        if isempty(candidates)
            wrapped = mod([b1 b2], period);
            candidates = wrapped;
            inRange = candidates >= 0 & candidates <= 100;
            candidates = candidates(inRange);
        end

        if isempty(candidates)
            error('No valid percent solution found in [0, 100] for requested power.');
        end

        modeled = A .* sin(omega .* candidates + phi) + D;
        [~, idx] = min(abs(modeled - power(i)));
        percent(i) = candidates(idx);
    end

    percent = double(percent(1));
end

function finalizeRunLog(hWP, runLog)
    try
        if isempty(runLog.endedAt_local)
            runLog.endedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
        end
        t0 = datetime(runLog.startedAt_local, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
        t1 = datetime(runLog.endedAt_local, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
        runLog.duration_s = seconds(t1 - t0);

        if strcmp(runLog.status, "running")
            runLog.status = "completed";
        end

        try
            runLog.finalMotorPosition_um = hWP.hSI.hMotors.samplePosition;
        catch
            runLog.finalMotorPosition_um = [NaN NaN NaN];
        end

        out = wpWriteScanRunArtifacts(hWP, runLog);
        if out.ok
            fprintf('[WP Log] Summary: %s\n', out.paths.summaryTxt);
            fprintf('[WP Log] Metadata: %s\n', out.paths.metadataJson);
            fprintf('[WP Log] Layers: %s\n', out.paths.layersCsv);
            fprintf('[WP Log] ScanPaths snapshot: %s\n', out.paths.scanPathsSnapshot);
        else
            warning('[WP Log] Failed to write run artifacts: %s', out.message);
        end
    catch ME
        warning('[WP Log] finalizeRunLog failed: %s', ME);
    end
end
