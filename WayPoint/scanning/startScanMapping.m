function startScanMapping(hWP)
%STARTSCANMAPPING Robust playback of precomputed scan paths across tiles + Z levels.
% 19/02/2026 9:04
%
% Robustness features added:
%   - Handles single-tile or multi-tile stacks (scanPaths normalized to column)
%   - Skips empty tiles / missing Z-levels / missing paths gracefully
%   - Ensures each scan path has >= 2 points (prevents zero-length playback)
%   - Correct scan-time estimate consistent with playPreexistingPath resampling
%   - Uses hWP.Settings.Power_pct (0..100) -> PowerFrac (0..1) with clamping
%   - Safer Z motion: sanity-check delta, move, then verify arrival tolerance
%   - (Optional) Finds X/Y galvo resources by name, with fallback to indices 118/119
%   - Checks Z-level quantization (0.01 µm) and warns/rounds to nearest step

    % ---- make sure isPaused and isCancelled are both false
    hWP.isCancelled = false;
    hWP.isPaused = false;

    % ---- time estimate for entire stack (your existing helper)
    figure
    [allTime_min, sliceTimes_min] = estimateScanMapTime(hWP);

    fprintf('Started at: %s\n', timeofday(datetime('now')));
    fprintf('Expected end: %s\n', timeofday(datetime('now')) + minutes(allTime_min));

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
    leadS = 0.004;
    tailS = 0.002;

    % ---- power (0..100 → 0..1)
    if ~isfield(hWP.Settings,'Power_pct') || isempty(hWP.Settings.Power_pct)
        error('hWP.Settings.Power_pct missing.');
    end
    Pf = max(0, min(1, double(hWP.Settings.Power_pct) / 100));

    % ---- Z constraints
    zStep_um          = 0.01;     % quantization step
    zMaxDeltaGuard   = 1200;     % absolute guardrail (µm)
    zArriveTol_um    = 0.05;     % arrival tolerance (µm)

    % ---- mask offset (single source of truth)

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

        % ========================================================
        % Z LOOP
        % ========================================================
        for zIdx = 1:numel(zLevels)

            if isempty(tilePaths{zIdx})
                continue;
            end

            zLocal = zLevels(zIdx);

            zWorld = zLocal + hWP.hMask.Position(3);
            realZ  = hWP.hSI.hMotors.samplePosition(:,3);
            

            % ---- guardrail
            if abs(realZ - zWorld) >= zMaxDeltaGuard
                warning('Refusing Z move: current %.2f µm, target %.2f µm (Δ=%.2f µm)', ...
                        realZ, zWorld, abs(realZ - zWorld));
                return;
            end

            % ---- move Z
            tic
            try
                hWP.hSI.hMotors.moveSample([0 0 zWorld]);
                try % plot on the figure
                    plot(x_um, y_um, '-')
                    axis equal
                catch
                    % do nothing
                end
                
                while hWP.hSI.hMotors.moveInProgress
                    pause(0.02);
                end
                
            catch ME
                warning('Z move failed (Tile %d Z %d): %s', tileIdx, zIdx, ME.message);
                continue;
            end
            toc

            realZ2 = hWP.hSI.hMotors.samplePosition(:,3);
            if abs(realZ2 - zWorld) > zArriveTol_um
                warning('Z arrival off: got %.3f µm, wanted %.3f µm', realZ2, zWorld);
            end

            % ---- XY path (translate AFTER Z success)
            scanPathXY = tilePaths{zIdx};
            scanPathXY = unique(scanPathXY, 'rows', 'stable');

            if size(scanPathXY,1) < 2
                fprintf('Tile %d Z %d: path too short, skipping.\n', tileIdx, zIdx);
                continue;
            end

            x_um = scanPathXY(:,1);
            y_um = scanPathXY(:,2);

            plot(x_um, y_um,'-k')

            % ---- bounds safety
            assert(all(abs(x_um)<=500 & abs(y_um)<=500), ...
                'Path exceeds ±500 µm bounds.');

            % ---- time estimate
            totalLength_um = sum(hypot(diff(x_um), diff(y_um)));
            estimatedTime_s = (totalLength_um / beamWaistDiameter_um) * PDT_s + leadS + tailS;

            fprintf('Tile %d Z %d   | Z=%.2f µm | %.3f s\n', ...
                    tileIdx, zIdx, zWorld, estimatedTime_s);

            % ---- execute scan
            
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
                continue;
            end
            
            drawnow % make sure pause updates

            % ---- PAUSE HERE (safe boundary)
            waitIfPaused(hWP);
            
            % ---- optional cancel check (future)
            if isprop(hWP,'isCancelled') && hWP.isCancelled
                warning('Scan cancelled by user.');
                return;
            end

            % % ---- progress UI
            % try
            %     updateTimeProgressBar(hWP, tileIdx, zIdx, allTime_min, sliceTimes_min);
            % catch
            % end
        end
    end % Double counting tranlated positions with .txt files (at least known for scanpaths on Feb 22, 2026)

    disp('DONE!');
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
