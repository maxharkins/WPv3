function tileScan(hWP, varargin)
% tileScan(hWP, 'StartPosition',[-600 -400], 'EndPosition',[600 400], 'ZoomFactor',6, 'TileOverlap',45, 'zLevels', -5:2.5:5, 'ScanOrder', 'TLRB', 'Snake', true)
    hSI = hWP.hSI;
    hSICtl = hWP.hSICtl;

    scanOrderOptions = {'TRLB', 'TLRB', 'BLRT', 'BRLT'};
    
    parser = inputParser;
    addRequired(parser, 'hWP');
    addParameter(parser, 'StartPosition', [], @(x) numel(x) == 2);
    addParameter(parser, 'EndPosition', [], @(x) numel(x) == 2);
    addParameter(parser, 'ZoomFactor', [], @(x) x>=1);
    addParameter(parser, 'TileOverlap', [], @(x) isvector(x));
    addParameter(parser, 'zLevels', 0, @(x) isvector(x));
    addParameter(parser, 'ScanOrder', 'TLRB', @(x) any(strcmp(scanOrderOptions, x)));
    addParameter(parser, 'Snake', false);
    
    parse(parser, hWP, varargin{:});
    StartPosition = parser.Results.StartPosition;
    EndPosition = parser.Results.EndPosition;
    ZoomFactor = parser.Results.ZoomFactor;
    TileOverlap = parser.Results.TileOverlap;
    zLevels = parser.Results.zLevels;
    ScanOrder = parser.Results.ScanOrder;
    Snake = parser.Results.Snake;

    
    TileSize = hWP.Settings.FOVSize_um;
    TileSpacing = TileSize - 2.*TileOverlap;
    
    rangeX = ceil(EndPosition(:,1) - StartPosition(:,1));
    rangeY = ceil(EndPosition(:,2) - StartPosition(:,2));

    numTilesX = ceil(rangeX / TileSpacing(1));
    numTilesY = ceil(rangeY / TileSpacing(2));

    tileCoords = zeros(numTilesX*numTilesY, 2);
    tileIdx = 1;
    for xPosition = StartPosition(1):TileSpacing(1):StartPosition(1) + rangeX
        for yPosition = StartPosition(2):TileSpacing(2):StartPosition(2) + rangeY
            tileCoords(tileIdx,:) = [xPosition, yPosition];
            tileIdx = tileIdx+1;
        end
    end
    tileCoords = floor(tileCoords/2.5)*2.5;
    stagePath = getOrderedTileCoords(tileCoords, ScanOrder, Snake);
    
    hWP.Sequence = ScanSequence(stagePath);
    hWP.Sequence.isAblation = 1;

    hWP.hWells(1).iPath = Path;
    hWP.hWells(1).iPath.Coordinates = stagePath;
    
    
    hWP.Sequence.ImageDir = startMosaicImaging(hWP, stagePath);
    writematrix(stagePath, fullfile(hWP.Sequence.ImageDir, 'StagePath.txt'));


end
        
function orderedCoords = getOrderedTileCoords(tileCoords, ScanOrder, Snake)
    % Input:
    %   tileCoords: An Nx2 array of x, y coordinates for each tile.
    %   ScanOrder: A string representing the scan order. Options: 'TRLB', 'TLRB', 'BLRT', 'BRLT'.
    %   Snake: A boolean flag that determines if the traversal is snake-like.
    %
    % Output:
    %   orderedCoords: An Nx3 array of ordered coordinates with zLevel (assumed to be constant).

    % Extract the number of rows and columns from tileCoords
    uniqueX = unique(tileCoords(:,1)); % Unique x-coordinates
    uniqueY = unique(tileCoords(:,2)); % Unique y-coordinates
    
    % Assuming that the coordinates are arranged in a grid-like pattern
    rows = length(uniqueY);
    cols = length(uniqueX);

    orderedCoords = zeros(rows * cols, 3); % Initialize the output array (N x 3)
    index = 1;  % Initialize the index for orderedCoords

    % Define row and column indices based on ScanOrder
    switch ScanOrder
        case 'TRLB'
            rowIndices = 1:rows;
            colIndices = cols:-1:1;
        case 'TLRB'
            rowIndices = 1:rows;
            colIndices = 1:cols;
        case 'BLRT'
            rowIndices = rows:-1:1;
            colIndices = 1:cols;
        case 'BRLT'
            rowIndices = rows:-1:1;
            colIndices = cols:-1:1;
        otherwise
            error('Invalid ScanOrder. Choose from TRLB, TLRB, BLRT, BRLT.');
    end

    % Iterate through rows and columns based on the scan order
    for r = rowIndices
        % Flip column order for snake-like traversal
        if Snake && mod(find(rowIndices == r, 1), 2) == 0
            colOrder = fliplr(colIndices);
        else
            colOrder = colIndices;
        end

        % For each column in the current row, get the corresponding coordinates from tileCoords
        for c = colOrder
            % Find the matching coordinates for the current row and column
            xValue = uniqueX(c);
            yValue = uniqueY(r);
            
            % Assign the coordinates and assume zLevels stay constant (or can be added here)
            orderedCoords(index, :) = [xValue, yValue, 0]; % zLevel is assumed to be 0 for now
            index = index + 1;
        end
    end
end




