function [allTime_min, sliceTimes_min] = estimateScanMapTime(hWP)
% estimateScanMapTime
% Robust scan-time estimator for single- or multi-tile stacks.
% Assumes scan paths are ordered XY points in microns.

    stack    = hWP.hStacks;
    scanPaths = stack.ScanPaths(:);          % enforce column
    numTiles = numel(scanPaths);

    % --- timing parameters
    PDT_ms = hWP.Settings.PixelDwellTime_ms; % milliseconds per sample
    PDT    = PDT_ms * 1e-3;                  % seconds per sample

    % --- spatial sampling assumption
    % Use XY spacing if available, otherwise assume 1 µm per sample
    if isfield(hWP.Settings,'XYSpacing_um') && ~isempty(hWP.Settings.XYSpacing_um)
        ds = hWP.Settings.XYSpacing_um;      % µm per sample
    else
        ds = 1.0;                            % conservative fallback
    end

    overheadFactor = 1.25;                   % galvo + command overhead

    allTime_s = 0;
    sliceTimes_min = cell(numTiles,1);

    for tileIdx = 1:numTiles
        tilePaths = scanPaths{tileIdx};
        if isempty(tilePaths)
            continue
        end

        if isrow(tilePaths), tilePaths = tilePaths.'; end

        zLevels = stack.ArbitraryZs{tileIdx};
        if isempty(zLevels)
            continue
        end
        zLevels = zLevels(:);

        numZ = min(numel(tilePaths), numel(zLevels));
        sliceTimes_min{tileIdx} = cell(numZ,1);

        tileTime_s = 0;

        for zIdx = 1:numZ
            pathXY = tilePaths{zIdx};
            if isempty(pathXY) || size(pathXY,1) < 2
                continue
            end

            % Remove duplicate consecutive points
            pathXY = unique(pathXY,'rows','stable');
            if size(pathXY,1) < 2
                continue
            end

            % --- geometric path length (µm)
            segLens = sqrt(sum(diff(pathXY).^2,2));
            totalLen_um = sum(segLens);

            if totalLen_um <= 0
                continue
            end

            % --- samples and time
            nSamples = ceil(totalLen_um / ds);
            estTime_s = nSamples * PDT * overheadFactor;

            tileTime_s = tileTime_s + estTime_s;
            sliceTimes_min{tileIdx}{zIdx} = estTime_s / 60;
        end

        fprintf('Tile %d: Estimated Time: %.3f min\n', ...
                tileIdx, tileTime_s/60);

        allTime_s = allTime_s + tileTime_s;
    end

    allTime_min = allTime_s / 60;
    fprintf('Estimated total time: %.3f min\n', allTime_min);

end