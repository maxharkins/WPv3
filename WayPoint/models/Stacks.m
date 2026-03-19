classdef Stacks < handle & matlab.mixin.SetGet
    %Updated FEB. 11, 2026
    properties % Stack Settings
        WellIndex
        isActive
        StagePath
    end
    properties % Ablation settings
        FramesPerSlice
        PixelDwellTime_ms
        Power_pct
    end
    properties
        PowerBoxes % Cell array for each tile and z-level
        ArbitraryZs
        ScanPaths
        ScanMeta   % Cell array mirroring ScanPaths; .isTravel mask per vertex
        LastImportStats
    end
    properties
        MeshEdgeLayers   % struct array from slicer
        isMeshScan = false
        isEffectively2D = false;
    end
    properties
        hWP
    end


    methods
        function obj = Stacks(app, isMeshScan)
            if nargin < 2
                isMeshScan = false;
            end
            if nargin < 1
                obj.isActive = false;
                return;
            end
        
            obj.isActive          = true;
            obj.StagePath         = app.aPath.Coordinates;
            obj.FramesPerSlice    = app.Settings.FramesPerSlice;
            obj.PixelDwellTime_ms = app.Settings.PixelDwellTime_ms;
            obj.Power_pct         = app.Settings.Power_pct;
        
            obj.ScanPaths     = {};
            obj.ScanMeta      = {};
            obj.PowerBoxes    = {};
            obj.ArbitraryZs   = {};
            obj.LastImportStats = struct();
            obj.isMeshScan    = isMeshScan;
            obj.hWP           = app;
        end

        function obj = buildScanPathsFromMeshLayers(obj, app)

            if isempty(obj.MeshEdgeLayers)
                error('MeshEdgeLayers is empty. Did you slice the STL first?');
            end


            % Redo the slice triangulation to scan paths since its pretty
            % fast and we want to make the z step size is still used.
            cfg = struct();
            rasterSpacing_um = wpRasterSpacingFromBeamWaist(app.Settings.BeamWaistDiameter_um);
            cfg.xySpacing = rasterSpacing_um;                   % µm
            cfg.zStep     = app.Settings.QuantFactorZ_um;       % µm
            cfg.verbose   = true;

            T = triangulation(app.hMask.hTri.ConnectivityList, app.hMask.hTri.BasePoints);
        
            layers = sliceTriangulationToScanPaths(T, cfg);
        
            %app.hStacks = Stacks(app, true);
            
            numZ = numel(layers);
        
            % Build as {numZ x 1} for this single mesh "tile"
            scanPath = cell(numZ,1);
            zLevels  = nan(numZ,1);
        
            for zIdx = 1:numZ
        
                contours = layers(zIdx).contours;
        
                % If your slicer stores z for each layer, prefer it
                if isfield(layers(zIdx), 'z')
                    zLevels(zIdx) = layers(zIdx).z;
                elseif isfield(layers(zIdx), 'Z')
                    zLevels(zIdx) = layers(zIdx).Z;
                else
                    % Fallback: assume uniform stepping
                    zLevels(zIdx) = (zIdx-1) * app.Settings.QuantFactorZ_um;
                end
        
                segs = contoursToScanSegments(contours, rasterSpacing_um);
        
                if isempty(segs)
                    scanPath{zIdx} = [];
                    continue
                end
        
                % midpoint logic
                midpointsXY    = [(segs(:,1)+segs(:,3))/2, segs(:,2)];
                halfDistances  = (segs(:,3)-segs(:,1))/2;
        
                midpointsXY_sorted = getHamiltonianPath(midpointsXY);
                if mod(zIdx, 1) == 0
                    fprintf("%d / %d\n",zIdx,numZ)
                end
                [~, order] = ismember(midpointsXY_sorted, midpointsXY, 'rows');
                halfDistances = halfDistances(order,:);
        
                pathXY = zeros(0,2);
        
                for b = 1:size(midpointsXY_sorted,1)
        
                    mp = midpointsXY_sorted(b,:);
                    hd = halfDistances(b);
        
                    epL = mp - [hd 0];
                    epR = mp + [hd 0];
        
                    if b == 1
                        pathXY = [epL; epR];
                    else
                        last = pathXY(end,:);
                        if norm(last - epL) < norm(last - epR)
                            pathXY = [pathXY; epL; epR];
                        else
                            pathXY = [pathXY; epR; epL];
                        end
                    end
                end
        
                scanPath{zIdx} = pathXY;
            end
        
            % IMPORTANT: wrap into a single tile to match legacy shape
            obj.ScanPaths   = {scanPath};   % {1 x 1} tile, tile{1} is {numZ x 1}
            obj.ScanMeta    = {cell(numZ,1)};
            obj.ArbitraryZs = {zLevels};    % {1 x 1} tile, tile{1} is [numZ x 1]
        end
        function obj = applyMaskOffsetToScanPaths(obj)
        
            if isempty(obj.hWP) || isempty(obj.hWP.hMask)
                return;
            end
        
            offset = obj.hWP.hMask.Position(:).';
        
            if all(offset == 0)
                return;
            end
        
            for t = 1:numel(obj.ScanPaths)
                tile = obj.ScanPaths{t};
                if isempty(tile), continue; end
        
                for z = 1:numel(tile)
                    if ~isempty(tile{z})
                        tile{z}(:,1:2) = tile{z}(:,1:2) + offset(1:2);
                    end
                end
        
                obj.ScanPaths{t} = tile;
            end
        
            % Z offset must be applied consistently
            if ~isempty(obj.ArbitraryZs)
                for t = 1:numel(obj.ArbitraryZs)
                    if ~isempty(obj.ArbitraryZs{t})
                        obj.ArbitraryZs{t} = obj.ArbitraryZs{t} + offset(3);
                    end
                end
            end
        end
        function obj = extrudeSingleLayer(obj, numCopies, zStep_um, filePath)
            % ------ Parameters ------
            if nargin < 4
                filePath = [];
            end
            % Basic validation (minimal)
            if ~(isscalar(numCopies) && numCopies >= 1 && numCopies == floor(numCopies))
                error('numCopies must be a positive integer.');
            end
            if ~(isscalar(zStep_um) && isfinite(zStep_um))
                error('zStep_um must be a finite scalar (microns).');
            end
        
            % ------ Build replicated ScanPaths from the first Z-path of each tile ------
            numTiles = numel(obj.ScanPaths);
            newScanPaths = cell(numTiles,1);
            newScanMeta  = cell(numTiles,1);
            newArbZs     = cell(numTiles,1);
        
            for tileIdx = 1:numTiles
                tileData = obj.ScanPaths{tileIdx};
                if isrow(tileData), tileData = tileData.'; end
        
                % Use the existing first Z slice as the base path
                if isempty(tileData) || isempty(tileData{1})
                    basePath = []; % allow empty
                else
                    basePath = tileData{1};
                end
        
                % Replicate the base path numCopies times (column cell)
                newScanPaths{tileIdx} = repmat({basePath}, numCopies, 1);
                if isprop(obj, 'ScanMeta') && numel(obj.ScanMeta) >= tileIdx && ~isempty(obj.ScanMeta{tileIdx})
                    tileMeta = obj.ScanMeta{tileIdx};
                    if isrow(tileMeta), tileMeta = tileMeta.'; end
                    if ~isempty(tileMeta) && ~isempty(tileMeta{1})
                        baseMeta = tileMeta{1};
                    else
                        baseMeta = zeros(size(basePath,1),1);
                    end
                else
                    baseMeta = zeros(size(basePath,1),1);
                end
                newScanMeta{tileIdx} = repmat({baseMeta}, numCopies, 1);
        
                % Establish base Z for this tile
                baseZ = 0;
                if isprop(obj,'ArbitraryZs') && ~isempty(obj.ArbitraryZs) ...
                        && numel(obj.ArbitraryZs) >= tileIdx && ~isempty(obj.ArbitraryZs{tileIdx})
                    b = obj.ArbitraryZs{tileIdx};
                    if ~isempty(b) && isfinite(b(1))
                        baseZ = b(1);
                    end
                end
        
                % Create Z levels in microns: baseZ + (0..numCopies-1)*zStep_um
                newArbZs{tileIdx} = baseZ + (0:numCopies-1).' * zStep_um;
            end
        
            % ------ Assign (this mutates obj if it is a handle class) ------
            obj.ScanPaths   = newScanPaths;
            obj.ScanMeta    = newScanMeta;
            obj.ArbitraryZs = newArbZs;
        
            % ------ Export (optional) ------
            if ~isempty(filePath)
                obj.exportScanPaths(filePath);
            end
        end

        function tf = queryIsEffectively2D(obj)
            tf = true;
        
            if isempty(obj.ArbitraryZs)
                return;
            end
        
            for t = 1:numel(obj.ArbitraryZs)
                zs = obj.ArbitraryZs{t};
                if isempty(zs)
                    continue;
                end
                zs = zs(:);
                if numel(unique(zs(~isnan(zs)))) > 1
                    tf = false;
                    return;
                end
            end
            
        end

        function obj = getScanPaths(obj, app)
            prepSequence(app)
            obj.isEffectively2D = false; % initialize

            importedExt = "";
            if isprop(app, 'Settings') && isstruct(app.Settings) && ...
                    isfield(app.Settings, 'ImportedFilePath') && ~isempty(app.Settings.ImportedFilePath)
                [~,~,ext] = fileparts(app.Settings.ImportedFilePath);
                importedExt = string(lower(ext));
            end
            if any(importedExt == [".gcode", ".gco", ".nc"]) && hasAnyPlayableScanPaths(obj.ScanPaths)
                fprintf('[Stacks] Using precomputed G-code scan paths from import (no regeneration).\n');
                obj.dispStats();
                return;
            end

            if obj.isMeshScan
                % ======================================================
                % STL / Mesh workflow
                % ======================================================
                if isempty(obj.MeshEdgeLayers)
                    T = triangulation(app.hMask.hTri.ConnectivityList, app.hMask.hTri.BasePoints); 
                    % ------------------------------------------------------------
                    % Build layered scan paths directly
                    % ------------------------------------------------------------
                    cfg = struct();
                    rasterSpacing_um = wpRasterSpacingFromBeamWaist(app.Settings.BeamWaistDiameter_um);
                    cfg.xySpacing = rasterSpacing_um;                   % µm
                    cfg.zStep     = app.Settings.QuantFactorZ_um;       % µm
                    cfg.verbose   = true;
                
                    layers = sliceTriangulationToScanPaths(T, cfg);
                    obj.MeshEdgeLayers = layers;
                end

                tic
                obj = obj.buildScanPathsFromMeshLayers(app); % slice it!!
                toc
                
                obj.dispStats();
                return;
            end
        
            % ==========================================================
            % Mask / node workflow (legacy but retained)
            % ==========================================================
        
            % Lazily build PowerBoxes
            obj = obj.PopulatePowerBoxes(app);
        
            stageSize_um          = zoom2microns(app.Zoom_Factor_Spinner.Value);
            beamWaistDiameter_um = app.Settings.BeamWaistDiameter_um;
        
            numTiles = numel(obj.PowerBoxes);
            obj.ScanPaths = cell(numTiles,1);
            obj.ScanMeta = cell(numTiles,1);
        
            for tileIdx = 1:numTiles
                tilePB = obj.PowerBoxes{tileIdx};
                numZs  = numel(tilePB);
        
                scanPath = cell(numZs,1);
        
                for zIdx = 1:numZs
                    img = tilePB{zIdx}.mask;
                    pathXY = getPathXYfromImg(img, stageSize_um, beamWaistDiameter_um);
                    scanPath{zIdx} = pathXY;

                    if mod(zIdx, 1) == 0
                        fprintf("%d / %d\n",zIdx,numZs)
                    end
                end
        
                obj.ScanPaths{tileIdx} = scanPath;
                obj.ScanMeta{tileIdx} = cellfun(@(p) zeros(size(p,1),1), scanPath, 'UniformOutput', false);
            end

            % ==========================================================
            % AUTO-EXTRUDE 2D PATHS IF REQUESTED
            % ==========================================================
            obj.isEffectively2D = obj.queryIsEffectively2D();
            if obj.isEffectively2D
            
                zStart = app.Extrusion_Z_Start_Edit_Field.Value;
                zEnd   = app.Extrusion_Z_End_Edit_Field.Value;
                zStep  = app.Extrusion_Z_Step_Size_Edit_Field.Value;
            
                if ~isempty(zStart) && ~isempty(zEnd) && ~isempty(zStep) && zEnd > zStart
            
                    numCopies = floor((zEnd - zStart) / zStep) + 1;
            
                    fprintf('[Stacks] Detected 2D scan paths. Auto-extruding:\n');
                    fprintf('  Z start: %.3f µm\n', zStart);
                    fprintf('  Z end  : %.3f µm\n', zEnd);
                    fprintf('  Z step : %.3f µm\n', zStep);
                    fprintf('  Layers : %d\n', numCopies);
            
                    % Shift base Z to start plane
                    for t = 1:numel(obj.ArbitraryZs)
                        obj.ArbitraryZs{t}(:) = zStart;
                    end
            
                    obj = obj.extrudeSingleLayer(numCopies, zStep);
            
                end
            end
            obj.dispStats();
        end
        function dispStats(obj)
            fprintf('\n================ STACK SUMMARY ================\n');
        
            numTiles = numel(obj.ScanPaths);
            fprintf('Tiles           : %d\n', numTiles);
        
            totalLayers = 0;
            for t = 1:numTiles
                nZ = numel(obj.ScanPaths{t});
                totalLayers = totalLayers + nZ;
                fprintf('  Tile %d layers : %d\n', t, nZ);
        
                if ~isempty(obj.ArbitraryZs) && numel(obj.ArbitraryZs) >= t
                    zs = obj.ArbitraryZs{t};
                    if ~isempty(zs)
                        fprintf('    Z range     : [%.3f, %.3f] µm\n', min(zs), max(zs));
                    end
                end
            end
        
            fprintf('Total Z layers  : %d\n', totalLayers);
        
            % Path statistics
            totalPoints = 0;
            for t = 1:numTiles
                for z = 1:numel(obj.ScanPaths{t})
                    p = obj.ScanPaths{t}{z};
                    if ~isempty(p)
                        totalPoints = totalPoints + size(p,1);
                    end
                end
            end
        
            fprintf('Total XY points : %d\n', totalPoints);
            fprintf('Mesh scan       : %d\n', obj.isMeshScan);
            fprintf('===============================================\n\n');
        end
        function exportScanPaths(obj, filename)
            % exportScanPaths writes ScanPaths to a readable, reversible text file.
            %
            %   obj.exportScanPaths('ScanPathsOutput.txt')
            %
            if nargin < 2 || isempty(filename)
                filename = 'ScanPaths.txt';
            end
        
            fid = fopen(filename, 'w');
            if fid == -1
                error('Could not open file %s for writing.', filename);
            end
            c = onCleanup(@() fclose(fid));
        
            % Expect {numTiles x 1}
            numTiles = numel(obj.ScanPaths);
            fprintf(fid, 'NumTiles: %d\n\n', numTiles);
        
            % Try to read per-tile Zs if present
            hasArbZs = isprop(obj,'ArbitraryZs') && ~isempty(obj.ArbitraryZs) && numel(obj.ArbitraryZs) >= numTiles;
        
            for tileIdx = 1:numTiles
                fprintf(fid, '--- Tile %d ---\n', tileIdx);
        
                % Expect tileData as {numZs x 1}; accept row and coerce in memory if needed
                tileData = obj.ScanPaths{tileIdx};
                if isrow(tileData)
                    tileData = tileData.';
                end
                numZs = numel(tileData);
                fprintf(fid, 'NumZs: %d\n', numZs);
        
                % Pull this tile's Z levels if available
                tileZs = [];
                if hasArbZs && ~isempty(obj.ArbitraryZs{tileIdx})
                    tileZs = obj.ArbitraryZs{tileIdx};
                    tileZs = tileZs(:); % column
                end
        
                for zIdx = 1:numZs
                    fprintf(fid, 'Z-Index: %d\n', zIdx);
        
                    % Write Z-Level (microns). If missing, write NaN to be explicit.
                    zval = NaN;
                    if ~isempty(tileZs) && numel(tileZs) >= zIdx && ~isempty(tileZs(zIdx))
                        zval = tileZs(zIdx);
                    end
                    fprintf(fid, 'Z-Level: %g\n', zval);
        
                    % Paths
                    try
                        pathXY = tileData{zIdx};
                    catch
                        pathXY = [];
                    end
        
                    if isempty(pathXY)
                        fprintf(fid, 'Empty\n\n');
                        continue;
                    end
        
                    % pathXY can be N x 2 (XY) or N x 3 (XYZ primitive).
                    if size(pathXY,2) >= 3
                        fprintf(fid, '%f %f %f\n', pathXY(:,1:3).');
                    else
                        fprintf(fid, '%f %f\n', pathXY(:,1:2).');
                    end
                    fprintf(fid, '\n');
                end
        
                fprintf(fid, '\n');
            end
        
            fprintf('ScanPaths successfully written to %s\n', filename);
        end

        function coords_XYZ = importAndCenterScanPaths(obj, filename)
        % importAndCenterScanPaths reconstructs obj.ScanPaths and obj.ArbitraryZs
        % from a text file written by exportScanPaths.
        %
        % ALSO:
        %   - Reconstructs full XYZ coordinate set
        %   - Centers XY using bounding-box midpoint
        %   - Shifts Z so minimum Z = 0
        %   - Assigns nodes to hMask.hNodes for plotting
        %   - Resets mask position to prevent double-translation
        %
        %   coords_XYZ = obj.importAndCenterScanPaths('ScanPathsOutput.txt')
        
            if nargin < 2 || isempty(filename)
                filename = 'ScanPaths.txt';
            end
        
            fid = fopen(filename, 'r');
            if fid == -1
                error('Could not open file %s for reading.', filename);
            end
        
            coords_XYZ = [];   % [N x 3] accumulator
        
            c = onCleanup(@() fclose(fid));
        
            scanPaths = {};
            scanMeta  = {};
            allZs     = {};
            tileIdx   = 0;
        
            currentTile = {};
            currentMeta = {};
            currentZs   = [];
            expectedNumZ = [];
        
            line = fgetl(fid);
        
            while ischar(line)
                s = strtrim(line);
        
                if startsWith(s, '--- Tile')
        
                    % Finalize previous tile
                    if ~isempty(currentTile)
                        if isrow(currentTile), currentTile = currentTile.'; end
                        if isrow(currentMeta), currentMeta = currentMeta.'; end
                        scanPaths{tileIdx,1} = currentTile;
                        if isempty(currentMeta)
                            currentMeta = cellfun(@(p) zeros(size(p,1),1), currentTile, 'UniformOutput', false);
                        end
                        scanMeta{tileIdx,1} = currentMeta;
                        if ~isempty(currentZs)
                            allZs{tileIdx,1} = currentZs(:);
                        else
                            allZs{tileIdx,1} = nan(numel(currentTile),1);
                        end
                    end
        
                    tileIdx = tileIdx + 1;
                    currentTile = {};
                    currentMeta = {};
                    currentZs   = [];
                    expectedNumZ = [];
        
                elseif startsWith(s, 'NumZs:')
                    nz = sscanf(s, 'NumZs: %d');
                    if ~isempty(nz) && isscalar(nz) && nz >= 0
                        expectedNumZ = nz;
                        currentTile  = cell(expectedNumZ,1);
                        currentMeta  = cell(expectedNumZ,1);
                        currentZs    = nan(expectedNumZ,1);
                    end
        
                elseif startsWith(s, 'Z-Index:')
                    zIdx = sscanf(s, 'Z-Index: %d');
                    if isempty(zIdx) || zIdx <= 0
                        error('Invalid Z-Index line: "%s"', s);
                    end
        
                    if isempty(expectedNumZ)
                        if numel(currentTile) < zIdx
                            currentTile{zIdx,1} = [];
                        end
                        if numel(currentMeta) < zIdx
                            currentMeta{zIdx,1} = [];
                        end
                        if numel(currentZs) < zIdx
                            currentZs(zIdx,1) = NaN;
                        end
                    end
        
                    coordLine = fgetl(fid);
                    while ischar(coordLine) && isempty(strtrim(coordLine))
                        coordLine = fgetl(fid);
                    end
        
                    % Optional Z-Level
                    if ischar(coordLine)
                        t1 = strtrim(coordLine);
                        if startsWith(t1, 'Z-Level:')
                            zval = sscanf(t1, 'Z-Level: %f');
                            if ~isempty(zval)
                                currentZs(zIdx,1) = zval;
                            end
                            coordLine = fgetl(fid);
                        end
                    end
        
                    coords = [];
                    while ischar(coordLine)
                        t = strtrim(coordLine);
                        if isempty(t)
                            break;
                        end
                        if strcmpi(t,'Empty')
                            coords = [];
                            coordLine = fgetl(fid);
                            while ischar(coordLine) && ~isempty(strtrim(coordLine))
                                coordLine = fgetl(fid);
                            end
                            break;
                        end
        
                        vals = sscanf(t,'%f');
                        if numel(vals) ~= 2 && numel(vals) ~= 3
                            error('Malformed coordinate line: "%s"', t);
                        end

                        if isempty(coords)
                            coords = nan(0, numel(vals));
                        elseif size(coords,2) ~= numel(vals)
                            maxCols = max(size(coords,2), numel(vals));
                            if maxCols > size(coords,2)
                                coords(:,end+1:maxCols) = nan;
                            end
                        end
                        row = nan(1, size(coords,2));
                        row(1:numel(vals)) = vals.';
                        coords(end+1,:) = row; %#ok<AGROW>
                        coordLine = fgetl(fid);
                    end
        
                    currentTile{zIdx,1} = coords;
                    if ~isempty(coords) && size(coords,2) >= 3 && isfinite(currentZs(zIdx))
                        currentMeta{zIdx,1} = abs(coords(:,3) - currentZs(zIdx)) > 1e-9;
                    else
                        currentMeta{zIdx,1} = zeros(size(coords,1),1);
                    end
        
                    % Accumulate global XYZ
                    if ~isempty(coords)
                        if size(coords,2) >= 3
                            coords_XYZ = [coords_XYZ; coords(:,1:3)]; %#ok<AGROW>
                        else
                            zval = currentZs(zIdx);
                            if ~isnan(zval)
                                coords_XYZ = [coords_XYZ; ...
                                              coords(:,1:2), repmat(zval,size(coords,1),1)]; %#ok<AGROW>
                            end
                        end
                    end
                end
        
                line = fgetl(fid);
            end
        
            % Finalize last tile
            if ~isempty(currentTile)
                if isrow(currentTile), currentTile = currentTile.'; end
                if isrow(currentMeta), currentMeta = currentMeta.'; end
                scanPaths{tileIdx,1} = currentTile;
                if isempty(currentMeta)
                    currentMeta = cellfun(@(p) zeros(size(p,1),1), currentTile, 'UniformOutput', false);
                end
                scanMeta{tileIdx,1} = currentMeta;
                if ~isempty(currentZs)
                    allZs{tileIdx,1} = currentZs(:);
                else
                    allZs{tileIdx,1} = nan(numel(currentTile),1);
                end
            end
        
            obj.ScanPaths   = scanPaths(:);
            obj.ScanMeta    = scanMeta(:);
            obj.ArbitraryZs = allZs(:);

            
            % ============================================================
            % BOUNDING-BOX CENTERING (XY AND Z)
            % ============================================================
            
            % ---- XY bounding-box centering
            xyMin = min(coords_XYZ(:,1:2), [], 1);
            xyMax = max(coords_XYZ(:,1:2), [], 1);
            xyCenter = (xyMin + xyMax) / 2;
            coords_XYZ(:,1:2) = coords_XYZ(:,1:2) - xyCenter;
            
            % ---- Z bounding-box centering
            zMin = min(coords_XYZ(:,3));
            zMax = max(coords_XYZ(:,3));
            zCenter = (zMin + zMax) / 2;
            coords_XYZ(:,3) = coords_XYZ(:,3) - zCenter;
            
            % ---- Apply SAME Z shift to ArbitraryZs
            if ~isempty(obj.ArbitraryZs)
                valid = ~isnan(obj.ArbitraryZs{:});
                obj.ArbitraryZs{:}(valid) = obj.ArbitraryZs{:}(valid) - zCenter;
            end        
            
            % ============================================================
            % NORMALIZE INTO MASK-LOCAL FRAME
            % ============================================================
            if ~isempty(coords_XYZ)        
                % ---- Z shift so min(Z) = 0
                zMin = min(coords_XYZ(:,3));
                coords_XYZ(:,3) = coords_XYZ(:,3) - zMin;
        
                % ========================================================
                % ASSIGN TO MASK NODES FOR PLOTTING
                % ========================================================
                obj.hWP.hMask.hNodes.BasePoints        = coords_XYZ;
                obj.hWP.hMask.hNodes.TransformedPoints = coords_XYZ;
                
            else
                warning('No XYZ coordinates reconstructed from %s', filename);
            end
        
            fprintf('ScanPaths loaded and centered from %s\n', filename);
        
        end

        function coords_XYZ = importAndCenterGCode(obj, filename, app)
        % importAndCenterGCode parses G-code extrusion moves and maps them
        % into tile-local ScanPaths with FOV clipping and overlap-aware tiling.
            if nargin < 3 || isempty(app)
                app = obj.hWP;
            end

            g = parseGCodeFile(filename, 'AssumeMMIsMicrons', true);
            moves = g.moves;
            moveIsTravel = g.moveIsTravel(:);
            moveIsExtrusion = g.moveIsExtrusion(:);
            coords_XYZ = g.xyz;

            if isempty(moves)
                warning('No XY moves found in %s', filename);
                obj.ScanPaths = {};
                obj.ScanMeta = {};
                obj.ArbitraryZs = {};
                return;
            end

            moveLen = hypot(moves(:,4) - moves(:,1), moves(:,5) - moves(:,2));
            zDelta = abs(moves(:,6) - moves(:,3));
            hopTol = 1e-9;
            travelHopMask = moveIsTravel & (zDelta > hopTol);
            obj.LastImportStats = struct( ...
                'source', 'gcode', ...
                'numMoves', size(moves,1), ...
                'numExtrusionMoves', sum(moveIsExtrusion), ...
                'numTravelMoves', sum(moveIsTravel), ...
                'numTravelHopMoves', sum(travelHopMask), ...
                'totalLength_um', sum(moveLen), ...
                'extrusionLength_um', sum(moveLen(moveIsExtrusion)), ...
                'travelLength_um', sum(moveLen(moveIsTravel)));
            fprintf('[GCODE Import] moves=%d | extrusion=%d | travel=%d | travel-hops=%d\n', ...
                obj.LastImportStats.numMoves, ...
                obj.LastImportStats.numExtrusionMoves, ...
                obj.LastImportStats.numTravelMoves, ...
                obj.LastImportStats.numTravelHopMoves);
            fprintf('[GCODE Import] length um: total=%.3f | extrusion=%.3f | travel=%.3f\n', ...
                obj.LastImportStats.totalLength_um, ...
                obj.LastImportStats.extrusionLength_um, ...
                obj.LastImportStats.travelLength_um);

            % Bounding-box center in XY.
            xyMin = min(coords_XYZ(:,1:2), [], 1);
            xyMax = max(coords_XYZ(:,1:2), [], 1);
            xyCenter = (xyMin + xyMax) / 2;
            coords_XYZ(:,1:2) = coords_XYZ(:,1:2) - xyCenter;
            moves(:,[1 2 4 5]) = moves(:,[1 2 4 5]) - repmat([xyCenter xyCenter], size(moves,1), 1);

            % G-code Z convention is opposite microscopy Z convention.
            coords_XYZ(:,3) = -coords_XYZ(:,3);
            moves(:,[3 6]) = -moves(:,[3 6]);

            % Keep raw imported Z levels as truth for G-code.
            % Shift so deepest plane is at Z=0 and superficial planes are negative.
            zMax = max(coords_XYZ(:,3));
            coords_XYZ(:,3) = coords_XYZ(:,3) - zMax;
            moves(:,[3 6]) = moves(:,[3 6]) - zMax;

            if any(moveIsExtrusion)
                zLevels = unique(moves(moveIsExtrusion,6), 'sorted');
            else
                % Fallback if file has XY motion but no explicit extrusion semantics.
                zLevels = unique(moves(:,6), 'sorted');
            end
            zLevels = zLevels(:);
            fprintf('[GCODE Import] extrusion Z levels: %d\n', numel(zLevels));

            if isempty(zLevels)
                warning('No valid Z levels detected in %s', filename);
                obj.ScanPaths = {};
                obj.ScanMeta = {};
                obj.ArbitraryZs = {};
                return;
            end

            fovSize = app.Settings.FOVSize_um;
            tileOverlap = app.Tile_Overlap_Edit_Field.Value;
            tileSpacing = fovSize - 2 * tileOverlap;
            if any(tileSpacing <= 0)
                error('Tile overlap is too large. FOV - 2*overlap must be positive.');
            end
            if isscalar(tileSpacing)
                tileSpacingXY = [tileSpacing tileSpacing];
            else
                tileSpacingXY = tileSpacing(:).';
            end

            stagePath = getStagePath(app, coords_XYZ, tileSpacing, 'ablation');
            numTiles = size(stagePath, 1);
            numZ = numel(zLevels);
            halfFov = fovSize / 2;
            ownerHalf = tileSpacingXY / 2;
            tol = 1e-9;

            scanPaths = cell(numTiles, 1);
            scanMeta = cell(numTiles, 1);
            allZs = cell(numTiles, 1);
            for tileIdx = 1:numTiles
                scanPaths{tileIdx} = cell(numZ, 1);
                scanMeta{tileIdx} = cell(numZ, 1);
                allZs{tileIdx} = zLevels;
            end

            for i = 1:size(moves,1)
                p0 = moves(i,1:2);
                p1 = moves(i,4:5);
                if norm(p1 - p0) <= tol
                    continue;
                end

                zRef = moves(i,6);
                [~, zIdx] = min(abs(zLevels - zRef));
                if isempty(zIdx) || ~isfinite(zRef)
                    continue;
                end
                zVal = zLevels(zIdx);
                isTravelMove = logical(moveIsTravel(i));

                for tileIdx = 1:numTiles
                    cxy = stagePath(tileIdx,1:2);
                    fovRect = [cxy(1)-halfFov, cxy(1)+halfFov, cxy(2)-halfFov, cxy(2)+halfFov];

                    % Ownership rectangle avoids duplicate exposure in overlap.
                    if numTiles == 1
                        ownerRect = fovRect;
                    else
                        ownerRect = [ ...
                            cxy(1)-ownerHalf(1), cxy(1)+ownerHalf(1), ...
                            cxy(2)-ownerHalf(2), cxy(2)+ownerHalf(2)];
                    end

                    assignRect = intersectRects(fovRect, ownerRect);
                    [tf, q0, q1] = clipSegmentToRect(p0, p1, assignRect);
                    if ~tf
                        continue;
                    end

                    local0 = q0 - cxy;
                    local1 = q1 - cxy;
                    [scanPaths{tileIdx}{zIdx}, scanMeta{tileIdx}{zIdx}] = appendMoveToPath( ...
                        scanPaths{tileIdx}{zIdx}, ...
                        scanMeta{tileIdx}{zIdx}, ...
                        local0, ...
                        local1, ...
                        zVal, ...
                        isTravelMove, ...
                        tol);
                end
            end

            obj.ScanPaths = scanPaths;
            obj.ScanMeta = scanMeta;
            obj.ArbitraryZs = allZs;
            obj.StagePath = stagePath;

            if ~isempty(app.aPath)
                app.aPath.Coordinates = stagePath;
            end

            obj.hWP.hMask.hNodes.BasePoints = coords_XYZ;
            obj.hWP.hMask.hNodes.TransformedPoints = coords_XYZ;

            fprintf('G-code loaded and converted to ScanPaths from %s\n', filename);
        end

        function obj = PopulatePowerBoxes(obj, app)
            stagePath   = obj.StagePath(:,1:2);
            nodes       = app.hMask.hNodes.TransformedPoints;
            tileSize    = app.Settings.FOVSize_um;
            resXY       = app.Settings.QuantFactorXY_um;
            powers      = app.Settings.Power_pct;
        
            tileBounds  = [stagePath - tileSize/2, stagePath + tileSize/2];
            maskSize    = round(tileSize ./ resXY);
        
            numTiles = size(tileBounds, 1);
        
            % Enforce column containers for tiles
            obj.PowerBoxes  = cell(numTiles, 1);
            obj.ArbitraryZs = cell(numTiles, 1);
        
            for tileIdx = 1:numTiles
                currentNodes = nodes( ...
                    nodes(:,1) >= tileBounds(tileIdx,1) & nodes(:,1) <= tileBounds(tileIdx,3) & ...
                    nodes(:,2) >= tileBounds(tileIdx,2) & nodes(:,2) <= tileBounds(tileIdx,4), :);
        
                if isempty(currentNodes)
                    obj.PowerBoxes{tileIdx,1}  = {};
                    obj.ArbitraryZs{tileIdx,1} = [];
                    continue;
                end
        
                uniqueZs = unique(currentNodes(:,3));
                uniqueZs = uniqueZs(:);                % ensure column
                numZs    = numel(uniqueZs);
        
                tilePowerBoxes = cell(numZs, 1);       % preallocate column
        
                for zIdx = 1:numZs
                    currentZ = uniqueZs(zIdx);
        
                    mask = zeros(maskSize, 'double');
        
                    nodesAtZ = currentNodes(currentNodes(:,3) == currentZ, :);
                    indices = [ ...
                        floor((nodesAtZ(:,1) - tileBounds(tileIdx,1)) ./ resXY) + 1, ...
                        floor((nodesAtZ(:,2) - tileBounds(tileIdx,2)) ./ resXY) + 1 ];
        
                    indices = max(min(indices, maskSize), 1);
        
                    for i = 1:size(indices, 1)
                        mask(indices(i,1), indices(i,2)) = 1;
                    end
        
                    if isempty(app.hSI)
                        pb = PowerBox;
                    else
                        pb = scanimage.components.beams.PowerBox();
                    end
                    pb.rect   = [0 0 1 1];
                    pb.mask   = mask;
                    pb.powers = powers/100;
                    pb.zs     = currentZ;
                    pb.name   = num2str(currentZ);
        
                    % Two-subscript indexing to keep column
                    tilePowerBoxes{zIdx,1} = pb;
                end
        
                obj.PowerBoxes{tileIdx,1}  = tilePowerBoxes;  % {numZs x 1}
                obj.ArbitraryZs{tileIdx,1} = uniqueZs;        % [numZs x 1 double]
            end
        end
    end
end

function [path, isTravel] = appendMoveToPath(path, isTravel, p0, p1, zVal, moveIsTravel, tol)
    if nargin < 7 || isempty(tol)
        tol = 1e-9;
    end
    if nargin < 2 || isempty(isTravel)
        isTravel = zeros(0,1);
    end
    if nargin < 1 || isempty(path)
        path = zeros(0,3);
    end

    if size(path,2) < 3 && ~isempty(path)
        path(:,3) = zVal;
    end
    if numel(isTravel) ~= size(path,1)
        isTravel = zeros(size(path,1),1);
    else
        isTravel = isTravel(:);
    end

    if norm(p1 - p0) <= tol
        return;
    end

    validRows = all(isfinite(path(:,1:3)), 2);
    if any(validRows)
        lastIdx = find(validRows, 1, 'last');
        lastXY = path(lastIdx,1:2);
        if norm(lastXY - p0) > tol
            path = [path; nan(1,3)];
            isTravel = [isTravel; 1];
        end
    end

    seg = [p0, zVal; p1, zVal];
    segTravel = repmat(logical(moveIsTravel), size(seg,1), 1);

    validRows = all(isfinite(path(:,1:3)), 2);
    if any(validRows)
        lastIdx = find(validRows, 1, 'last');
        if all(abs(path(lastIdx,:) - seg(1,:)) <= tol)
            seg = seg(2:end,:);
            segTravel = segTravel(2:end,:);
        end
    end

    if ~isempty(seg)
        path = [path; seg];
        isTravel = [isTravel; segTravel];
    end
end

function [tf, q0, q1] = clipSegmentToRect(p0, p1, rect)
% rect = [xmin xmax ymin ymax]
    xmin = rect(1);
    xmax = rect(2);
    ymin = rect(3);
    ymax = rect(4);

    if xmin > xmax || ymin > ymax
        tf = false;
        q0 = [nan nan];
        q1 = [nan nan];
        return;
    end

    dx = p1(1) - p0(1);
    dy = p1(2) - p0(2);

    p = [-dx, dx, -dy, dy];
    q = [p0(1)-xmin, xmax-p0(1), p0(2)-ymin, ymax-p0(2)];

    t0 = 0;
    t1 = 1;

    for k = 1:4
        if abs(p(k)) < eps
            if q(k) < 0
                tf = false;
                q0 = [nan nan];
                q1 = [nan nan];
                return;
            end
        else
            r = q(k) / p(k);
            if p(k) < 0
                t0 = max(t0, r);
            else
                t1 = min(t1, r);
            end
            if t0 > t1
                tf = false;
                q0 = [nan nan];
                q1 = [nan nan];
                return;
            end
        end
    end

    q0 = p0 + t0 * [dx dy];
    q1 = p0 + t1 * [dx dy];
    tf = true;
end

function rectOut = intersectRects(a, b)
    rectOut = [max(a(1), b(1)), min(a(2), b(2)), max(a(3), b(3)), min(a(4), b(4))];
end

function tf = hasAnyPlayableScanPaths(scanPaths)
    tf = false;
    if isempty(scanPaths)
        return;
    end
    for t = 1:numel(scanPaths)
        tile = scanPaths{t};
        if isempty(tile) || ~iscell(tile)
            continue;
        end
        for z = 1:numel(tile)
            p = tile{z};
            if ~isempty(p) && size(p,1) >= 2 && size(p,2) >= 2
                tf = true;
                return;
            end
        end
    end
end
