function [pathXY] = getPathXYfromImg(img, stageSize, beamWaist)
    if nargin < 3 || isempty(beamWaist)
        beamWaist = 0.8; % microns per pixel
    end
    if nargin < 2 || isempty(stageSize)
        stageSize = round(size(img,1));
    end

    stageSize = round(stageSize(1));

    imgRes = size(img,1) / stageSize;
    desRes = 1/beamWaist;

    % scale img
    img = rot90(img,1);
    img = imresize(img, desRes/imgRes, 'nearest');

    [row, col] = find(img == 1);
    center = ([size(img,2), size(img,1)] + 1) / 2;
    coords = [col, row] - center;             % [x_px, y_px] centered

    coords = unique(round(coords),'row', 'stable');
    % ------------------------------------------------------------
    % PATCH MISSING y = 0 ROW (rounding parity hole)
    % ------------------------------------------------------------
    ys = unique(coords(:,2));
    
    if ~ismember(0, ys)
    
        % Expected lattice spacing in pixels (should be 1 after rounding)
        dy = min(diff(sort(ys)));
    
        % Find nearest rows above and below zero
        yNeg = max(ys(ys < 0));
        yPos = min(ys(ys > 0));
    
        if ~isempty(yNeg) && ~isempty(yPos) && abs(yPos - yNeg) <= 2*dy
    
            % Collect x-coverage from neighboring rows
            xNeg = coords(coords(:,2) == yNeg, 1);
            xPos = coords(coords(:,2) == yPos, 1);
    
            % Conservative fill: union of both rows
            xFill = unique([xNeg; xPos]);
    
            % Construct missing row
            newRow = [xFill, zeros(numel(xFill),1)];
    
            % Insert and re-sort
            coords = [coords; newRow];
            coords = unique(coords,'rows','stable');
            coords = sortrows(coords,[2 1]);
    
        end
    end
    
    if isempty(coords)
        pathXY = [];
        return
    end



    %% Get path
    [rectangles] = getSplitRectangles(coords, 1);
           
    [midpointsXY, halfDistances] = rectangles_to_midpoints(rectangles);

    midpointsXY_sorted = getHamiltonianPath(midpointsXY);
    % Find the reordering indices applied to midpointsXY
    [~, order] = ismember(midpointsXY_sorted, midpointsXY, 'rows');
    
    % Reorder halfDistances to match the sorted midpoints
    halfDistances = halfDistances(order, :);
    
    % Replace original midpointsXY with sorted version
    midpointsXY = midpointsXY_sorted;

    pathXY = zeros(0,2);
    for b = 1:size(midpointsXY, 1)
        mp_CURR = midpointsXY(b, :);
        hd_CURR = halfDistances(b, :);
        ep_L_CURR = mp_CURR - [hd_CURR,0];
        ep_R_CURR = mp_CURR + [hd_CURR,0];
        if b == 1
            pathXY = [pathXY; ep_L_CURR; ep_R_CURR];
            continue;
        end
        lastPoint = pathXY(end, :);
        if norm(lastPoint - ep_L_CURR) < norm(lastPoint - ep_R_CURR)
            pathXY = [pathXY; ep_L_CURR; ep_R_CURR];
        else
            pathXY = [pathXY; ep_R_CURR; ep_L_CURR];
        end
    end
    pathXY = pathXY * beamWaist;

end

function [midpointsXY, halfDistances] = rectangles_to_midpoints(rectangles)
    segs = rects_to_segments(rectangles);
    xL = min(segs(:,1), segs(:,3));
    xR = max(segs(:,1), segs(:,3));
    y  = segs(:,2);
    S = [xL y xR y];
    S = sortrows(S, [2 1]);
    midpointsXY = [(S(:,1)+S(:,3))/2, S(:,2)];
    halfDistances = (S(:,3)-S(:,1))/2;
end

function segs = rects_to_segments(rectangles)
    segs = zeros(0,4);
    for r = 1:size(rectangles,1)
        x0 = rectangles(r,1);
        y0 = rectangles(r,2);
        w  = rectangles(r,3);
        h  = rectangles(r,4);
        if h <= 0 || w <= 0, continue; end
        for yy = y0 : (y0 + h - 1)
            xL = x0;
            xR = x0 + w - 1;
            segs(end+1, :) = [xL, yy, xR, yy]; %#ok<AGROW>
        end
    end
end

    
        