function importFile(obj, filePath)
% Updated FEB. 11, 2026, 10:52
    % ------------------------------------------------------------
    % Select file
    % ------------------------------------------------------------
    if nargin < 2
        startDir = resolveDefaultImportDir();
        [file, path] = uigetfile(fullfile(startDir, '*.*'), 'Select import file');
        if isequal(file, 0)
            filePath = [];
        else
            filePath = fullfile(path, file);
        end
    end
    
    if isempty(filePath)
        return;
    end

    % Keep source file context for export naming + metadata logging.
    try
        src = wpRememberImportedFile(obj, filePath);
        obj.Settings.ImportedFilePath = src.path;
        obj.Settings.ImportedFileLabel = src.label;
    catch
    end

    wellCentroid = [0 0 0];   % Well coordinate frame origin
    [~,~,ext] = fileparts(filePath);
    ext = lower(ext);

    % ------------------------------------------------------------
    % Clear previous import state before loading new content
    % ------------------------------------------------------------
    obj.hMask = Mask();
    obj.hStacks = Stacks.empty;
    if ~isempty(obj.aPath)
        obj.aPath.Coordinates = [];
    end
    refreshPlot(obj);

    % ------------------------------------------------------------
    % Dispatch by file type
    % ------------------------------------------------------------
    switch ext

        case '.stl'
        
            % ------------------------------------------------------------
            % Parse STL → triangulation
            % ------------------------------------------------------------
            vol = parseSTLFile(filePath);
            vol = applyScaleRotateAndCenter(vol); % GUI step
            T = triangulation(vol.faces, vol.xyz); 
            % ------------------------------------------------------------
            % Build layered scan paths directly
            % ------------------------------------------------------------
            cfg = struct();
            cfg.xySpacing = wpRasterSpacingFromBeamWaist(obj.Settings.BeamWaistDiameter_um);  % µm
            cfg.zStep     = obj.Settings.QuantFactorZ_um;       % µm
            cfg.verbose   = true;
        
            layers = sliceTriangulationToScanPaths(T, cfg);
        
            obj.hStacks = Stacks(obj, true);
            obj.hStacks.MeshEdgeLayers = layers;

            obj.hMask.hTri.BasePoints        = T.Points;
            obj.hMask.hTri.TransformedPoints = T.Points;   % identity for now
            obj.hMask.hTri.ConnectivityList  = T.ConnectivityList;
            
            % Do NOT build paths yet
            refreshZSliceSelectionUI(obj, true);
            refreshPlot(obj);
            return;
            
        case '.txt'
            obj.hStacks = Stacks(obj);
            obj.hStacks.isMeshScan = 0; %VERY IMPORTANT


            if isScanPathTXT(filePath)
            
                coords_XYZ = obj.hStacks.importAndCenterScanPaths(filePath);
                if isempty(coords_XYZ)
                    warning('ScanPath file contained no valid coordinates.');
                end
            
                refreshZSliceSelectionUI(obj, true);
                refreshPlot(obj);
                return;
            end        
            data = parseTXTFile(filePath);
            dataType = classifyTXTData(data);
        
            switch dataType
        
                case 'Volume3D'
                    % data.raw is Nx3 XYZ
                    xyz = data.raw;
        
                    % purely numeric normalization (no faces)
                    xyz = applyScaleRotateAndCenter(struct('raw', xyz));
        
                    assignMask(obj, xyz.raw, wellCentroid);
        
                case 'Mask2D'
                    % data.raw is Nx2 XY
                    xy = data.raw;
        
                    % ensure uniqueness
                    xy = unique(xy, 'rows');
        
                    % promote to 3D using current stage Z
                    z0  = obj.hStage.Position(3);
                    xyz = [xy, repmat(z0, size(xy,1), 1)];
        
                    % normalize as point data
                    xyz = applyScaleRotateAndCenter(struct('raw', xyz));
        
                    assignMask(obj, xyz.raw, wellCentroid);
        
                case 'ScanPath'

                    coords_XYZ = obj.hStacks.importAndCenterScanPaths(filePath);
                
                    % Optional safety check
                    if isempty(coords_XYZ)
                        warning('ScanPath file loaded but contained no coordinates.');
                    end
                
                    refreshZSliceSelectionUI(obj, true);
                    refreshPlot(obj);
                    return;
        
                otherwise
                    error('Unrecognized TXT data format.');
            end

        case {'.gcode', '.gco', '.nc'}
            obj.hStacks = Stacks(obj);
            obj.hStacks.isMeshScan = 0;

            coords_XYZ = obj.hStacks.importAndCenterGCode(filePath, obj);
            if isempty(coords_XYZ)
                warning('G-code file loaded but contained no usable XY moves.');
            end

            refreshZSliceSelectionUI(obj, true);
            refreshPlot(obj);
            return;

        otherwise
            error('Unsupported file type: %s', ext);
    end

    % ------------------------------------------------------------
    % UI refresh
    % ------------------------------------------------------------
    refreshPlot(obj);
end

function startDir = resolveDefaultImportDir()
% Prefer known Zhang&Brown import roots inside Box.
    zhangBrownDir = wpFindZhangBrownFolder('StartDir', pwd);
    if ~isempty(zhangBrownDir)
        candidates = {
            fullfile(zhangBrownDir, 'Scan Objects')
            fullfile(zhangBrownDir, 'ScanObjects')
            zhangBrownDir
        };
        for i = 1:numel(candidates)
            if isfolder(candidates{i})
                startDir = candidates{i};
                return;
            end
        end
    end

    startDir = pwd;
end
