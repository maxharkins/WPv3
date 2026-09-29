function [allTime_min, sliceTimes_min] = estimateScanMapTime(hWP)
% estimateScanMapTime
% Robust scan-time estimator for single- or multi-tile stacks.
% Assumes scan paths are ordered XY points in microns.

    stack    = hWP.hStacks;
    scanPaths = stack.ScanPaths(:);          % enforce column
    numTiles = numel(scanPaths);
    hasMeta = isprop(stack, 'ScanMeta') && ~isempty(stack.ScanMeta);

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
        if hasMeta && numel(stack.ScanMeta) >= tileIdx && ~isempty(stack.ScanMeta{tileIdx})
            tileMeta = stack.ScanMeta{tileIdx};
            if isrow(tileMeta), tileMeta = tileMeta.'; end
        else
            tileMeta = cell(numel(tilePaths), 1);
        end

        zLevels = stack.ArbitraryZs{tileIdx};
        if isempty(zLevels)
            continue
        end
        zLevels = zLevels(:);

        numZ = min([numel(tilePaths), numel(zLevels), numel(tileMeta)]);
        tilePaths = tilePaths(1:numZ);
        tileMeta = tileMeta(1:numZ);
        zLevels = zLevels(1:numZ);
        selected = getSelectedZSliceIndices(hWP, zLevels);
        tilePaths = tilePaths(selected);
        tileMeta = tileMeta(selected);
        zLevels = zLevels(selected);
        numZ = numel(selected);
        sliceTimes_min{tileIdx} = cell(numZ,1);

        tileTime_s = 0;

        for zIdx = 1:numZ
            pathXY = tilePaths{zIdx};
            if isempty(pathXY) || size(pathXY,1) < 2
                continue
            end

            layerMeta = tileMeta{zIdx};
            chunks = buildPlaybackChunks(pathXY, layerMeta, zLevels(zIdx), 1e-9);
            if isempty(chunks)
                continue
            end

            totalLen_um = 0;
            numPlayableChunks = 0;
            for pIdx = 1:numel(chunks)
                sp = chunks(pIdx).xy;
                if size(sp,1) < 2
                    continue
                end
                totalLen_um = totalLen_um + sum(hypot(diff(sp(:,1)), diff(sp(:,2))));
                numPlayableChunks = numPlayableChunks + 1;
            end

            if totalLen_um <= 0 || numPlayableChunks == 0
                continue
            end

            estTime_s = (totalLen_um / rasterSpacing_um) * PDT_s + ...
                        numPlayableChunks * (leadS + tailS);

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
