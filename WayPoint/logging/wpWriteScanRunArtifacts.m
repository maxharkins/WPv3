function out = wpWriteScanRunArtifacts(hWP, runLog)
%WPWRITESCANRUNARTIFACTS Write machine + human readable scan run artifacts.

    out = struct('ok', false, 'paths', struct(), 'message', '');
    if nargin < 2 || isempty(runLog)
        out.message = 'No runLog provided.';
        return;
    end

    ctx = [];
    try
        ctx = wpEnsureDailyExperimentFolder('Create', true, 'DateTime', datetime('now'));
    catch ME
        out.message = ME.message;
        return;
    end

    runId = wpSanitizeLabel(runLog.runId);
    stamp = wpSanitizeLabel(runLog.startedAt_local);

    metaJsonPath = fullfile(ctx.subdirs.metadata, sprintf('%s_metadata.json', runId));
    metaMatPath = fullfile(ctx.subdirs.metadata, sprintf('%s_metadata.mat', runId));
    summaryPath = fullfile(ctx.subdirs.log, sprintf('%s_summary.txt', runId));
    layersPath = fullfile(ctx.subdirs.log, sprintf('%s_layers.csv', runId));
    scanPathsPath = fullfile(ctx.subdirs.processed, sprintf('%s_scanpaths_snapshot.txt', runId));

    % Attach output locations before serializing.
    runLog.outputs = struct( ...
        'metadataJson', metaJsonPath, ...
        'metadataMat', metaMatPath, ...
        'summaryTxt', summaryPath, ...
        'layersCsv', layersPath, ...
        'scanPathsSnapshot', scanPathsPath, ...
        'experimentDayDir', ctx.dayDir, ...
        'stamp', stamp);

    % JSON (machine-readable)
    try
        txt = jsonencode(runLog, 'PrettyPrint', true);
        fid = fopen(metaJsonPath, 'w');
        fwrite(fid, txt, 'char');
        fclose(fid);
    catch ME
        out.message = sprintf('Failed JSON write: %s', ME.message);
    end

    % MAT snapshot (full-fidelity reproducibility)
    try
        save(metaMatPath, 'runLog');
    catch
    end

    % Per-layer CSV
    try
        writeLayersCsv(layersPath, runLog.layers);
    catch
    end

    % Human-readable summary
    try
        writeSummary(summaryPath, runLog, ctx);
    catch
    end

    % Snapshot planned ScanPaths as exported text.
    try
        if isprop(hWP, 'hStacks') && ~isempty(hWP.hStacks) && isvalid(hWP.hStacks)
            hWP.hStacks.exportScanPaths(scanPathsPath);
        end
    catch
    end

    out.ok = true;
    out.paths = runLog.outputs;
end

function writeLayersCsv(filePath, layers)
    fid = fopen(filePath, 'w');
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'tile_idx,z_idx,z_local_um,z_world_um,estimated_time_s,path_points,path_length_um,status,error_message,start_local,end_local,move_delta_um\n');
    if isempty(layers)
        return;
    end

    for i = 1:numel(layers)
        rec = layers(i);
        err = stringOrEmpty(getFieldOr(rec, 'error', ''));
        err = strrep(err, ',', ';');
        fprintf(fid, '%d,%d,%.6f,%.6f,%.6f,%d,%.6f,%s,%s,%s,%s,%.6f\n', ...
            getFieldOr(rec, 'tileIdx', -1), ...
            getFieldOr(rec, 'zIdx', -1), ...
            getFieldOr(rec, 'zLocal_um', NaN), ...
            getFieldOr(rec, 'zWorld_um', NaN), ...
            getFieldOr(rec, 'estimatedTime_s', NaN), ...
            getFieldOr(rec, 'pathPointCount', 0), ...
            getFieldOr(rec, 'pathLength_um', NaN), ...
            stringOrEmpty(getFieldOr(rec, 'status', '')), ...
            err, ...
            stringOrEmpty(getFieldOr(rec, 'startedAt_local', '')), ...
            stringOrEmpty(getFieldOr(rec, 'endedAt_local', '')), ...
            getFieldOr(rec, 'zMoveDelta_um', NaN));
    end
end

function writeSummary(filePath, runLog, ctx)
    fid = fopen(filePath, 'w');
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    fprintf(fid, 'WayPoint Scan Run Summary\n');
    fprintf(fid, '========================\n\n');
    fprintf(fid, 'Run ID: %s\n', stringOrEmpty(getFieldOr(runLog, 'runId', '')));
    fprintf(fid, 'Status: %s\n', stringOrEmpty(getFieldOr(runLog, 'status', '')));
    fprintf(fid, 'Started: %s\n', stringOrEmpty(getFieldOr(runLog, 'startedAt_local', '')));
    fprintf(fid, 'Ended: %s\n', stringOrEmpty(getFieldOr(runLog, 'endedAt_local', '')));
    fprintf(fid, 'Duration (s): %.3f\n', getFieldOr(runLog, 'duration_s', NaN));
    fprintf(fid, '\nExperiment Day Folder: %s\n', ctx.dayDir);
    fprintf(fid, 'Log Folder: %s\n', ctx.subdirs.log);
    fprintf(fid, 'Metadata Folder: %s\n', ctx.subdirs.metadata);
    fprintf(fid, 'Processed Folder: %s\n', ctx.subdirs.processed);
    fprintf(fid, 'Calibration Folder: %s\n', getFieldOr(ctx.subdirs, 'calibration', ''));

    settings = getFieldOr(runLog, 'settings', struct());
    fprintf(fid, '\nSettings Snapshot\n');
    fprintf(fid, '-----------------\n');
    fprintf(fid, 'Power (%%): %.4f\n', getFieldOr(settings, 'Power_pct', NaN));
    fprintf(fid, 'Power (mW at objective): %.4f\n', getFieldOr(settings, 'Power_mW', NaN));
    fprintf(fid, 'Pixel Dwell Time (ms): %.6f\n', getFieldOr(settings, 'PixelDwellTime_ms', NaN));
    fprintf(fid, 'Beam Waist (um): %.6f\n', getFieldOr(settings, 'BeamWaistDiameter_um', NaN));
    fprintf(fid, 'Quant XY (um): %.6f\n', getFieldOr(settings, 'QuantFactorXY_um', NaN));
    fprintf(fid, 'Quant Z (um): %.6f\n', getFieldOr(settings, 'QuantFactorZ_um', NaN));
    fprintf(fid, 'Traversal: %s\n', stringOrEmpty(getFieldOr(settings, 'ZTraversalMode', '')));
    cal = getFieldOr(settings, 'PockelsCalibration', struct());
    rmseAcceptedVal = getFieldOr(cal, 'RMSEAccepted', NaN);
    if isnumeric(rmseAcceptedVal) || islogical(rmseAcceptedVal)
        rmseAcceptedText = num2str(double(logical(rmseAcceptedVal)));
    else
        rmseAcceptedText = 'NaN';
    end
    fprintf(fid, '\nPockels Calibration Snapshot\n');
    fprintf(fid, '---------------------------\n');
    fprintf(fid, 'Transfer factor downstream/objective (x): %.6f\n', getFieldOr(cal, 'powerEfficiency', NaN));
    fprintf(fid, 'Fit RMSE downstream (W): %.6f\n', getFieldOr(cal, 'RMSE', NaN));
    fprintf(fid, 'RMSE accepted: %s\n', rmseAcceptedText);
    fprintf(fid, 'Calibration MAT path: %s\n', stringOrEmpty(getFieldOr(getFieldOr(cal, 'paths', struct()), 'mat', '')));
    fprintf(fid, 'Calibration metadata path: %s\n', stringOrEmpty(getFieldOr(getFieldOr(cal, 'paths', struct()), 'metadataTxt', '')));

    counts = getFieldOr(runLog, 'counts', struct());
    fprintf(fid, '\nExecution Counts\n');
    fprintf(fid, '----------------\n');
    fprintf(fid, 'Tiles total: %d\n', getFieldOr(counts, 'tilesTotal', 0));
    fprintf(fid, 'Layers attempted: %d\n', getFieldOr(counts, 'layersAttempted', 0));
    fprintf(fid, 'Layers completed: %d\n', getFieldOr(counts, 'layersCompleted', 0));
    fprintf(fid, 'Layers skipped: %d\n', getFieldOr(counts, 'layersSkipped', 0));
    fprintf(fid, 'Layers failed: %d\n', getFieldOr(counts, 'layersFailed', 0));

    importInfo = getFieldOr(runLog, 'importedFile', struct());
    fprintf(fid, '\nImported Source\n');
    fprintf(fid, '---------------\n');
    fprintf(fid, 'Path: %s\n', stringOrEmpty(getFieldOr(importInfo, 'path', '')));
    fprintf(fid, 'Label: %s\n', stringOrEmpty(getFieldOr(importInfo, 'label', '')));
end

function val = getFieldOr(s, fieldName, fallback)
    if isstruct(s) && isfield(s, fieldName)
        val = s.(fieldName);
    else
        val = fallback;
    end
end

function s = stringOrEmpty(v)
    if isstring(v)
        s = char(v);
    elseif ischar(v)
        s = v;
    else
        s = '';
    end
end
