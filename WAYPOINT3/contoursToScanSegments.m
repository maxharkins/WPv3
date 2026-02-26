function segs = contoursToScanSegments(contours, ySpacing)

% segs = [xL y xR y] rows

segs = zeros(0,4);

for c = 1:numel(contours)

    poly = contours{c};
    if size(poly,1) < 3
        continue
    end

    yMin = min(poly(:,2));
    yMax = max(poly(:,2));

    yVals = yMin:ySpacing:yMax;

    for y = yVals

        % Intersect horizontal line with polygon
        xInts = intersectHorizontalLine(poly, y);

        if numel(xInts) < 2
            continue
        end

        xInts = sort(xInts);

        % Pair intersections
        for k = 1:2:numel(xInts)-1
            xL = xInts(k);
            xR = xInts(k+1);

            if xR > xL
                segs(end+1,:) = [xL y xR y]; %#ok<AGROW>
            end
        end
    end
end
end