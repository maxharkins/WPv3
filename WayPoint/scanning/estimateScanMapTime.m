function [allTime_min, sliceTimes_min] = estimateScanMapTime(hWP)
% estimateScanMapTime
% Robust scan-time estimator for single- or multi-tile stacks.
% Assumes scan paths are ordered XY points in microns.

    stack    = hWP.hStacks;
    scanPaths = stack.ScanPaths(:);          % enforce column
    numTiles = numel(scanPaths);

    % Match startScanMapping timing model.
    PDT_s = hWP.Settings.PixelDwellTime_ms / 1000;          % seconds
    beamWaistDiameter_um = hWP.Settings.BeamWaistDiameter_um; % µm
    rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um);
    leadS = 0.004;
    tailS = 0.002;

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

            subPaths = splitPathByNaN(pathXY);
            if isempty(subPaths)
                continue
            end

            totalLen_um = 0;
            numPlayableSubPaths = 0;
            for pIdx = 1:numel(subPaths)
                sp = unique(subPaths{pIdx}, 'rows', 'stable');
                if size(sp,1) < 2
                    continue
                end
                totalLen_um = totalLen_um + sum(hypot(diff(sp(:,1)), diff(sp(:,2))));
                numPlayableSubPaths = numPlayableSubPaths + 1;
            end

            if totalLen_um <= 0 || numPlayableSubPaths == 0
                continue
            end

            estTime_s = (totalLen_um / rasterSpacing_um) * PDT_s + ...
                        numPlayableSubPaths * (leadS + tailS);

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

function parts = splitPathByNaN(pathXY)
    parts = {};
    if isempty(pathXY) || size(pathXY,2) < 2
        return;
    end

    isBreak = any(isnan(pathXY), 2);
    startIdx = 1;
    for i = 1:size(pathXY,1)
        if isBreak(i)
            if i-1 >= startIdx
                seg = pathXY(startIdx:i-1, :);
                if size(seg,1) >= 2
                    parts{end+1,1} = seg; %#ok<AGROW>
                end
            end
            startIdx = i + 1;
        end
    end

    if startIdx <= size(pathXY,1)
        seg = pathXY(startIdx:end, :);
        if size(seg,1) >= 2
            parts{end+1,1} = seg; %#ok<AGROW>
        end
    end
end
