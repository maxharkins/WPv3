classdef AblationSequence
    properties
        StagePath
        hScanTiles      % Handle to ScanTiles class

        hWP                 % Handle to WP class
        hSI                 % Handle to SI class
        hSICtl              % Handle to SICtl class
    end

    methods
        function [obj] = AblationSequence(hWP, hSI, hSICtl)
            if nargin < 3
                hSICtl = evalin('base', 'hSICtl');
            end
            if nargin < 2
                hSI = evalin('base', 'hSI');
            end
            if nargin < 1
                hWP = evalin('base', 'hWP');
            end
            obj.hSICtl = hSICtl;
            obj.hSI = hSI;
            obj.hWP = hWP;
        end


        function [angles] = computeGalvoAngles(obj, xyCoords, stagePosXY)
            % Normalize x and y coordinates to galvo scan angles (-9.56° to 9.56°)
            xyCoords = xyCoords - (max(xyCoords) + min(xyCoords))/2;
            
            %uit Stage size and galvo limits
            stageSize = obj.hWP.hStage.Size(1:2);  % [xSize, ySize]
            thetaMax = 6;  % Max galvo scan angle
            
            % Normalize xyCoords to stagePosition
            zeroedCoords = xyCoords - stagePosXY;  % No need for stageSize/2 here
            
            % Clamp coordinates to make sure they are within [0, stageSize]
            clampedCoords = zeroedCoords;
                % max(min(zeroedCoords, stageSize), 0); 
                % disp(min(clampedCoords));
                % disp(max(clampedCoords));

            % Normalize clamped coordinates to [0, 1] (relative to the stage size)
            normalizedCoords = clampedCoords ./ stageSize; 
            disp(min(normalizedCoords));
            disp(max(normalizedCoords))
            
            % Map normalized coordinates to galvo scan angles (-thetaMax to +thetaMax)
            angles = normalizedCoords * (2 * thetaMax); 
            
            % Optional: Display the min and max angles for debugging
            disp('Min angle: ');
            disp(min(angles));
            disp('Max angle: ');
            disp(max(angles));
        end

        
        function [obj] = generateScanInstructions(obj, tileIdx)
            % Extract waypoints for the tile
            waypoints = obj.hScanTiles{tileIdx}.BeamWaypoints;
            numLayers = numel(waypoints);
            stagePosXY = obj.hWP.hAblationSequence.StagePath(tileIdx, 1:2);
        
            if isempty(waypoints)
                warning('No beam waypoints for tile %d', tileIdx);
                return;
            end
        
            blankThreshold = obj.hWP.settings.BlankDistance;
            dwellTime = obj.hWP.settings.PixelDwellTime;
            instructions = struct('Action', {}, 'Value', {}, 'Timestamp', {}); % Store scan instructions
        
            for zIdx = 1:numLayers
                currentZ = obj.hScanTiles{tileIdx}.UniqueZs(zIdx);
                xyPoints = waypoints{zIdx};
        
                if isempty(xyPoints)
                    continue;
                end
        
                % Convert to galvo scan angles
                scanAngles = obj.computeGalvoAngles(xyPoints, stagePosXY);
        
                % Optimize path (snake pattern per layer)
                optimizedPath = obj.optimizePath2D(scanAngles);
                xyPoints = obj.optimizePath2D(xyPoints);


                
                
                % Check distances for beam blanking
                numPoints = size(optimizedPath, 1);
                for i = 1:numPoints-1
                    dist = norm(xyPoints(i+1,:) - xyPoints(i,:));
                    %disp(dist)
                    if dist > blankThreshold
                        % Turn beam off for long jump
                        instructions(end+1) = struct('Action', 'Blank', 'Value', 1, 'Timestamp', []);
                    end
                
                    % Add move command with timestamp
                    instructions(end+1) = struct('Action', 'Move', 'Value', optimizedPath(i,:), 'Timestamp', tic/4);

                    if dist > blankThreshold || i == 1
                        % Turn beam back on
                        instructions(end+1) = struct('Action', 'Blank', 'Value', 0, 'Timestamp', []);
                    end
                end
                
                % Turn off the beam at the end
                instructions(end+1) = struct('Action', 'Blank', 'Value', 1, 'Timestamp', []);
            end
        
            % Store instructions in ScanTiles
            obj.hScanTiles{tileIdx}.ScanInstructions = instructions;
        end
        
        function obj = optimizeTileWaypoints(obj, tileIdx)
            % Get waypoints for the selected tile
            waypoints = obj.hScanTiles{tileIdx}.BeamWaypoints;
            numLayers = numel(waypoints);
        
            if isempty(waypoints)
                warning('No beam waypoints available for tile %d', tileIdx);
                return;
            end
        
            % Aggregate all waypoints across Z-layers
            allPoints = obj.hScanTiles{tileIdx}.Nodes;
        
            % Ensure we have valid waypoints
            if isempty(allPoints)
                warning('No valid waypoints for tile %d', tileIdx);
                return;
            end
        
            % Optimize path with simple layer-by-layer traversal
            optimizedPath = obj.optimizePath3D(allPoints);
        
            % Store the optimized path for execution later
            obj.hScanTiles{tileIdx}.OptimizedPath = optimizedPath;
        end
        
        function optimizedPath = optimizePath3D(obj, beamWaypoints)
            % Sort by Z in descending order (start at highest Z)
            beamWaypoints = sortrows(beamWaypoints, -3);
        
            % Process each Z layer independently
            uniqueZs = unique(beamWaypoints(:,3), 'stable');
            optimizedPath = [];
        
            for z = uniqueZs'
                layerPoints = beamWaypoints(beamWaypoints(:,3) == z, :);
        
                % Sort by Y descending first (top-to-bottom), then X (left-to-right for odd rows, right-to-left for even)
                layerPoints = obj.optimizePath2D(layerPoints(:,1:2));
        
                % Reassemble with Z values
                optimizedPath = [optimizedPath; [layerPoints, repmat(z, size(layerPoints,1), 1)]];
            end
        end
        
        function optimizedPath = optimizePath2D(obj, xyPoints)
            % Simple snake pattern in XY (starts top-left)
            
            % Sort by Y descending (top to bottom)
            xyPoints = sortrows(xyPoints, -2);
        
            % Process in a snake pattern
            numPoints = size(xyPoints, 1);
            optimizedPath = zeros(size(xyPoints));
        
            currentRow = 1;
            while currentRow <= numPoints
                % Find points at the same Y level
                yValue = xyPoints(currentRow, 2);
                rowEnd = currentRow;
                while rowEnd <= numPoints && xyPoints(rowEnd, 2) == yValue
                    rowEnd = rowEnd + 1;
                end
                rowEnd = rowEnd - 1;
        
                % Extract the row
                subRow = xyPoints(currentRow:rowEnd, :);
        
                % Alternate sorting direction
                if mod(currentRow, 2) == 1
                    subRow = sortrows(subRow, 1); % Left to right
                else
                    subRow = sortrows(subRow, -1); % Right to left
                end
        
                % Store results
                optimizedPath(currentRow:rowEnd, :) = subRow;
        
                % Move to next row
                currentRow = rowEnd + 1;
            end
        end
        
        function executeScan(obj, tileIdx)
            % Retrieve precomputed scan instructions
            instructions = obj.hScanTiles{tileIdx}.ScanInstructions;
        
            if isempty(instructions)
                warning('No scan instructions for tile %d', tileIdx);
                return;
            end
        
            dwellTime = obj.hWP.settings.PixelDwellTime; % PDT from settings
            disp(numel(instructions))
            pause(2)
            for i = 1:numel(instructions)
                switch instructions(i).Action
                    case 'Move'
                        % Get elapsed time
                        elapsedTime = toc(instructions(i).Timestamp);
        
                        % Wait for dwell time if needed
                        if elapsedTime < dwellTime
                            pause(dwellTime - elapsedTime);
                        end
        
                        % Move scanner
                        obj.hSI.hScan2D.pointScannerRef([instructions(i).Value(1), instructions(i).Value(2)]);
                        
                        %pause(8e-6)
                    case 'Blank'
                        if instructions(i).Value == 1 % then blank is true, and it should blank
                            obj.hSI.hScan2D.hBeams{1}.setPowerFraction(0);
                            pause(5e-4); % Small delay for blanking
                        else
                            obj.hSI.hScan2D.hBeams{1}.setPowerFraction(1);
                            pause(5e-4);
                        end
                end
            end
        end



        function [obj] = getBeamWaypoints(obj, MaskIdx)
            % Extract necessary settings and data
            stagePath   = obj.StagePath(:,1:2);
            nodes       = obj.hWP.hWells(MaskIdx).hMask.hNodes.TransformedPoints;
            tileSize    = obj.hWP.Settings.FOVSize_um;
            resolution  = obj.hWP.settings.quantFactor;            % Resolution [x y z]
            powers      = obj.hWP.settings.power;                  % Power levels
        
            % Calculate tile bounds for all stage path entries
            tileBounds = [stagePath - tileSize / 2, stagePath + tileSize / 2]; % Nx4 array [xmin, ymin, xmax, ymax]
            maskSize = round(tileSize ./ resolution(1:2));     % 2D mask size [rows, cols]
            
            numTiles = size(tileBounds, 1);

            obj.hScanTiles  = cell(numTiles, 1);
            for tileIdx = 1:numTiles
                obj.hScanTiles{tileIdx} = ScanTiles(tileIdx, stagePath(tileIdx, :), [], [], [], [], 100);

                % Find nodes within the current tile bounds
                currentNodes = nodes(...
                    nodes(:, 1) >= tileBounds(tileIdx, 1) & nodes(:, 1) <= tileBounds(tileIdx, 3) & ...
                    nodes(:, 2) >= tileBounds(tileIdx, 2) & nodes(:, 2) <= tileBounds(tileIdx, 4), :);

                if isempty(currentNodes)
                    continue;                    
                end

                % Get unique z-levels in the current tile
                uniqueZs = sort(unique(currentNodes(:,3)), 'descend');
                obj.hScanTiles{tileIdx}.Nodes = currentNodes;
                obj.hScanTiles{tileIdx}.UniqueZs = uniqueZs;
                obj.hScanTiles{tileIdx}.BeamWaypoints = cell(numel(uniqueZs), 1); % Initialize properly

                for zIdx = 1:numel(uniqueZs)
                    currentZ = uniqueZs(zIdx);
            
                    % Get nodes corresponding to the current Z level
                    nodesAtZ = currentNodes(currentNodes(:,3) == currentZ, :);
                    
                    if isempty(nodesAtZ)
                        continue;
                    end
            
                    % Translate node coordinates into mask indices
                    indices = [
                        floor((nodesAtZ(:,1) - tileBounds(tileIdx,1)) ./ resolution(1)) + 1, ...
                        floor((nodesAtZ(:,2) - tileBounds(tileIdx,2)) ./ resolution(2)) + 1  
                    ];
            
                    % Clamp indices to stay within bounds
                    indices = max(min(indices, maskSize), 1);
            
                    % Store the waypoints in sorted order
                    if size(indices,1) > 1
                        obj.hScanTiles{tileIdx}.BeamWaypoints{zIdx} = sortrows(indices, [1, 2]);
                    else
                        obj.hScanTiles{tileIdx}.BeamWaypoints{zIdx} = indices; % No sorting needed for single entry
                    end
                end
            end
        end

        


        % 
        % 
        % 
        % function scanWaypointsOptimized(obj, tileIdx)
        %     % Get waypoints for the selected tile
        %     waypoints = obj.hScanTiles{tileIdx}.BeamWaypoints;
        %     numLayers = numel(waypoints);
        % 
        %     if isempty(waypoints)
        %         warning('No beam waypoints available for tile %d', tileIdx);
        %         return;
        %     end
        % 
        %     % Iterate through each Z-layer
        %     for zIdx = 1:numLayers
        %         currentZ = obj.hScanTiles{tileIdx}.UniqueZs(zIdx);
        %         xyPoints = waypoints{zIdx};  % Extract XY waypoints for this Z level
        % 
        %         if isempty(xyPoints)
        %             continue;
        %         end
        % 
        %         % Optimize path using TSP or raster pattern
        %         optimizedPath = obj.optimizePath(xyPoints);
        % 
        %         % Interpolate waypoints for smoother transitions
        %         interpolatedPath = obj.interpolatePath(optimizedPath);
        % 
        %         % Scan waypoints with adaptive dwell time
        %         obj.scanWithDwellTime(interpolatedPath, currentZ);
        %     end
        % end
        % 
        % function optimizedPath = optimizePath(obj, waypoints)
        %     % Sort waypoints to minimize travel distance (TSP Approximation)
        % 
        %     numPoints = size(waypoints, 1);
        %     if numPoints < 2
        %         optimizedPath = waypoints;
        %         return;
        %     end
        % 
        %     % Nearest Neighbor (Greedy TSP Approximation)
        %     optimizedPath = zeros(size(waypoints));
        %     usedIdx = false(numPoints, 1);
        %     optimizedPath(1, :) = waypoints(1, :);
        %     usedIdx(1) = true;
        % 
        %     for i = 2:numPoints
        %         lastPoint = optimizedPath(i-1, :);
        %         dists = sum((waypoints - lastPoint).^2, 2);
        %         dists(usedIdx) = inf;
        %         [~, minIdx] = min(dists);
        %         optimizedPath(i, :) = waypoints(minIdx, :);
        %         usedIdx(minIdx) = true;
        %     end
        % end
        % 
        % function interpolatedPath = interpolatePath(obj, waypoints)
        %     % Interpolates waypoints for smooth motion (Bezier/Cubic Spline)
        % 
        %     if size(waypoints, 1) < 3
        %         interpolatedPath = waypoints; % No need for interpolation
        %         return;
        %     end
        % 
        %     t = linspace(0, 1, size(waypoints,1)); % Parameterize original points
        %     tInterp = linspace(0, 1, 5 * size(waypoints,1)); % Higher resolution
        % 
        %     % Cubic spline interpolation
        %     xInterp = interp1(t, waypoints(:,1), tInterp, 'pchip'); % Preserve shape
        %     yInterp = interp1(t, waypoints(:,2), tInterp, 'pchip');
        % 
        %     interpolatedPath = [xInterp', yInterp'];
        % end
        % 
        % function scanWithDwellTime(obj, waypoints, z)
        %     % Adjust dwell time dynamically based on speed
        % 
        %     numPoints = size(waypoints, 1);
        %     baseDwell = obj.hWP.settings.PDT; % Base dwell time (adjustable)
        % 
        %     for i = 1:numPoints-1
        %         % Compute distance to next point
        %         dist = norm(waypoints(i+1,:) - waypoints(i,:));
        % 
        %         % Adaptive dwell: More time for larger movements
        %         dwellTime = baseDwell + (dist * 2e-6); 
        % 
        %         % Move galvos & set dwell time
        %         obj.hSI.hScan2D.SlmScan.pointScanner(waypoints(i,1), waypoints(i,2), z); % MAY NEED TO EDIT
        %         pause(dwellTime); % Dwell at each point
        %     end
        % end
    end
end
