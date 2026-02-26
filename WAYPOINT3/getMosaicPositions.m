function [positions] = getMosaicPositions(MosaicSize, varargin)
    % Generates a set of 3D positions for a tile-based scanning pattern
    %
    % Inputs:
    %   MosaicSize - [rows, cols] specifying the number of tiles in each direction
    %   TileSize   - [width, height] specifying the size of each tile
    %   TileOverlap - [xOverlap, yOverlap] specifying the overlap between tiles (default: 0)
    %   zLevels    - Fixed Z-coordinate for all positions (default: 0)
    %   ScanOrder  - Specifies the tile scanning order, options:
    %                'TRLB' (Top-Right, Left, Bottom)
    %                'TLRB' (Top-Left, Right, Bottom)
    %                'BLRT' (Bottom-Left, Right, Top)
    %                'BRLT' (Bottom-Right, Left, Top)
    %   Snake      - Boolean flag to apply snaking pattern (default: false)
    %
    % Output:
    %   positions - Nx3 matrix where N = rows * cols, each row is [X, Y, Z]
    
    ScanOrderOptions = {'TRLB', 'TLRB', 'BLRT', 'BRLT'};
    
    parser = inputParser;
    addRequired(parser, 'MosaicSize',        @(x) isvector(x));
    addParameter(parser, 'zLevels', 0,        @(x) isvector(x));
    addParameter(parser, 'ScanOrder', 'TLRB', @(x) any(strcmp(ScanOrderOptions, x)));
    addParameter(parser, 'TileSpacing', [],  @(x) isvector(x));
    addParameter(parser, 'TileSize',    [],  @(x) isvector(x));
    addParameter(parser, 'TileOverlap', [],  @(x) isvector(x));
    addParameter(parser, 'Snake', false);
    
    parse(parser, MosaicSize, varargin{:});

    MosaicSize  = parser.Results.MosaicSize;
    zLevels     = parser.Results.zLevels;
    ScanOrder   = parser.Results.ScanOrder;
    TileSpacing = parser.Results.TileSpacing;
    TileSize    = parser.Results.TileSize;
    TileOverlap = parser.Results.TileOverlap;
    Snake       = parser.Results.Snake;

    if isscalar(MosaicSize); MosaicSize = MosaicSize * [1 1]; end
    if isempty(TileSpacing)
        if isempty(TileSize) || isempty(TileOverlap)
            error('Must include tile spacing or tile size and overlap.')
        end
        if isscalar(TileSize); TileSize = TileSize * [1 1]; end
        if isscalar(TileOverlap); TileOverlap = TileOverlap * [1 1]; end
        TileSpacing = TileSize - 2.*TileOverlap;
    end

    rows = MosaicSize(1);
    cols = MosaicSize(2);

    positions = zeros(rows * cols, 3);
    index = 1;

    if numel(TileSpacing) == 2
        xSpacing = TileSpacing(1);
        ySpacing = TileSpacing(2);
    else
        [xSpacing, ySpacing] = deal(TileSpacing);
    end

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

    for r = rowIndices
        if Snake && mod(find(rowIndices == r, 1), 2) == 0
            colOrder = fliplr(colIndices);
        else
            colOrder = colIndices;
        end

        yValue = (r - 1) * ySpacing;
        for c = colOrder
            xValue = (c - 1) * xSpacing;
            positions(index, :) = [xValue, yValue, zLevels];
            index = index + 1;
        end
    end
end