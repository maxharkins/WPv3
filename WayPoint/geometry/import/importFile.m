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

    wellCentroid = [0 0 0];   % Well coordinate frame origin
    [~,~,ext] = fileparts(filePath);
    ext = lower(ext);

    % ------------------------------------------------------------
    % Clear previous import state before loading new content
    % ------------------------------------------------------------
    obj.hMask = Mask();
    obj.hStacks = Stacks.empty;
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
            cfg.xySpacing = obj.Settings.BeamWaistDiameter_um;  % µm
            cfg.zStep     = obj.Settings.QuantFactorZ_um;       % µm
            cfg.verbose   = true;
        
            layers = sliceTriangulationToScanPaths(T, cfg);
        
            obj.hStacks = Stacks(obj, true);
            obj.hStacks.MeshEdgeLayers = layers;

            obj.hMask.hTri.BasePoints        = T.Points;
            obj.hMask.hTri.TransformedPoints = T.Points;   % identity for now
            obj.hMask.hTri.ConnectivityList  = T.ConnectivityList;
            
            % Do NOT build paths yet
            refreshPlot(obj);
            return;
            
        case '.txt'
            obj.hStacks = Stacks(obj);
            obj.hStacks.isMeshScan = 0; %VERY IMPORTANT


            if isScanPathTXT(filePath)
            
                coords_XYZ= obj.hStacks.importAndCenterScanPaths(filePath);
                zMin = min(coords_XYZ(:,3));
                zMax = max(coords_XYZ(:,3));
                zCenter = (zMin + zMax) / 2;
                coords_XYZ(:,3) = coords_XYZ(:,3) - zCenter;
                obj.hMask.hNodes.BasePoints = coords_XYZ;

                if isempty(obj.hMask.hNodes.BasePoints)
                    warning('ScanPath file contained no valid coordinates.');
                end
            
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
                warning('G-code file loaded but contained no extrusion coordinates.');
            end

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
% Prefer known Box import roots across macOS and workstation Windows.
    macTailPrimary = {'Zhang&Brown', 'Scan Objects'};
    macTailAlt     = {'Zhang&Brown', 'ScanObjects'};
    winTailPrimary = {'Zhang&Brown'};
    winTailAlt1    = {'Zhang&Brown', 'Scan Objects'};
    winTailAlt2    = {'Zhang&Brown', 'ScanObjects'};
    homeDir = char(java.lang.System.getProperty('user.home'));

    % First, walk up from cwd and use the first Box* ancestor.
    cursor = pwd;
    while true
        [parent, name] = fileparts(cursor);
        if startsWith(name, 'Box')
            candidates = {
                fullfile(cursor, macTailPrimary{:})
                fullfile(cursor, macTailAlt{:})
                fullfile(cursor, winTailPrimary{:})
                fullfile(cursor, winTailAlt1{:})
                fullfile(cursor, winTailAlt2{:})
            };
            for k = 1:numel(candidates)
                if isfolder(candidates{k})
                    startDir = candidates{k};
                    return;
                end
            end
        end

        if isempty(parent) || strcmp(parent, cursor)
            break;
        end
        cursor = parent;
    end

    searchPaths = {
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box-Box', macTailPrimary{:})
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box-Box', macTailAlt{:})
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box', macTailPrimary{:})
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box', macTailAlt{:})
        fullfile(homeDir, 'Box', macTailPrimary{:})
        fullfile(homeDir, 'Box', macTailAlt{:})
    };

    if ispc
        userProfile = getenv('USERPROFILE');
        if ~isempty(userProfile)
            searchPaths = [searchPaths; { ...
                fullfile(userProfile, 'Box', winTailPrimary{:}); ...
                fullfile(userProfile, 'Box', winTailAlt1{:}); ...
                fullfile(userProfile, 'Box', winTailAlt2{:}); ...
                fullfile(userProfile, 'Box-Box', winTailPrimary{:}); ...
                fullfile(userProfile, 'Box-Box', winTailAlt1{:}); ...
                fullfile(userProfile, 'Box-Box', winTailAlt2{:}) ...
            }]; %#ok<AGROW>
        end

        % Explicit workstation path.
        searchPaths = [searchPaths; { ...
            fullfile('C:\Users\SCIENTIFICA\Box', winTailPrimary{:}); ...
            fullfile('C:\Users\SCIENTIFICA\Box', winTailAlt1{:}); ...
            fullfile('C:\Users\SCIENTIFICA\Box', winTailAlt2{:}) ...
        }]; %#ok<AGROW>
    end

    for i = 1:numel(searchPaths)
        candidate = searchPaths{i};
        if isfolder(candidate)
            startDir = candidate;
            return;
        end
    end

    startDir = pwd;
end
