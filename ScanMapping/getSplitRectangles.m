



function [rectangles] = getSplitRectangles(coordinates_orig, quantFactor)
    if isempty(coordinates_orig) || quantFactor ==0 
        if quantFactor == 0
            disp('Quant Factor is 0.')
        end
        rectangles = [];
        return;
    end
    % Split into Nx1 rectangles
    coordinates = coordinates_orig/quantFactor;
    coordinates = unique(coordinates, 'rows');
    rectangles = [];

    for y = min(coordinates(:,2)):max(coordinates(:,2))
        [rectangleData] = splitRects_sequence(y, coordinates);
        rectangles = [rectangles; rectangleData];
    end
    rectangles = rectangles*quantFactor;
    rectangles(1:2) = rectangles(1:2) * [1 0; 0 1];



    function [rectangleData] = splitRects_sequence(y, coordinates)
        [coordsAtY] = getCoordsAtY(y, coordinates);
        if ~isempty(coordsAtY)
            [isLastInSegment] = checkIfLastInSegment(coordsAtY);
            [rectangleData] = getRectangleData(y, coordsAtY, isLastInSegment);
        else
            rectangleData = [];
        end
    end
    
    function [coordsAtY] = getCoordsAtY(y, coordinates)
        coordsAtY_condition = (coordinates(:,2) == y);
        coordsAtY = coordinates(coordsAtY_condition, 1); % 1D array, x values at that y layer
    end
    
    function [isLastInSegment] = checkIfLastInSegment(coordsAtY)
        if ~isempty(coordsAtY)
            isLastInSegment = ones(size(coordsAtY));
            if length(coordsAtY) > 1
                if coordsAtY(1)+1 == coordsAtY(2)
                    isLastInSegment(1) = 0;
                end
                for i = 2:length(coordsAtY)
                    try 
                        if coordsAtY(i)+1 == coordsAtY(i+1)
                            isLastInSegment(i) = 0;
                        end
                    catch
                        % on last index it will stay '1'.
                    end
                end
            end
            
        else
            isLastInSegment = [];
        end
    end
    
    function [rectangleData] = getRectangleData(y, coordsAtY, isLastInSegment)
        % rectangleData is an array with lower x bound, lower y bound, length, and width
        rectangleData = zeros(sum(isLastInSegment), 4);
        
        [segmentLengths] = getSegmentLengths(coordsAtY, isLastInSegment);
        breaksIndex = find(isLastInSegment == 1);
    
        if ~isempty(segmentLengths)
            rectangleData(1,:) = [min(coordsAtY), y, segmentLengths(1), 1];
            if length(segmentLengths) > 1
                a = 2;
                for i = 2:length(segmentLengths)
                    rectangleData(a,:) = [coordsAtY((breaksIndex(i-1))+1), y, segmentLengths(i), 1];
                    a = a+1;
                end
            end
        else
            error('Array "segmentLengths" is empty.')
        end
    end
    
    function [segmentLengths] = getSegmentLengths(coordsAtY, isLastInSegment)
        segmentLengths = zeros(sum(isLastInSegment), 1);
        currentSegmentLength = 0;
        segmentIndex = 1;
        if ~isempty(coordsAtY)
            for i = 1:length(coordsAtY)
                currentSegmentLength = currentSegmentLength +1;
                if isLastInSegment(i)
                    segmentLengths(segmentIndex) = currentSegmentLength;
                    currentSegmentLength = 0;
                    segmentIndex = segmentIndex +1;
                end
            end
        else
            error('Array "segmentLengths" is empty.')
        end
    end
end