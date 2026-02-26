function [path, initialDistance, adjustedDistance] = getHamiltonianPath(coordinates)
    startIdx = 1;
    numPoints = size(coordinates, 1);
    path = zeros(numPoints, 2);
    path(1, :) = coordinates(startIdx, :);

    visited = false(numPoints, 1);
    visited(startIdx) = true;
    order = zeros(numPoints, 1);
    order(1) = startIdx;

    % --- Defensive: close any stale waitbars (optional but helpful)
    try
        delete(findall(0,'Type','figure','Tag','TMWWaitbar'));
    catch
        % ignore
    end

    % --- Try to create waitbar, but tolerate failure/interruption
    h = [];
    % try
    %     h = waitbar(0,'Progress','Name','Progress');
    %     % ensure it closes even on errors or Ctrl-C
    %     cleaner = onCleanup(@() (isvalid_scalar(h) && close(h)));
    % catch
    %     % Could not create a waitbar (headless/Ctrl-C during drawnow/etc.)
    %     h = [];
    % end
    h = [];
    % Throttle UI updates by wall time
    tLast = tic;

    for i = 2:numPoints
        lastPoint = path(i-1, :);
        remainingIdx = find(~visited);
        remainingCoords = coordinates(remainingIdx, :);
        nearestIdx = knnsearch(remainingCoords, lastPoint);
        nextIdx = remainingIdx(nearestIdx);

        path(i, :) = coordinates(nextIdx, :);
        visited(nextIdx) = true;
        order(i) = nextIdx;

        % Safe, throttled update only if the bar exists and is valid
        if ~isempty(h) && isvalid_scalar(h) && (toc(tLast) > 0.1 || i == numPoints)
            % try
            %     %waitbar(i/numPoints, h, sprintf('Progress: %d%%', floor(100*i/numPoints)));
            %     drawnow limitrate nocallbacks
            %     tLast = tic;
            % catch
            %     % If the bar was closed or interrupted mid-update, stop using it
            %     try, if isvalid_scalar(h), close(h); end, end %#ok<TRYNC>
            %     h = [];
            % end
        end
    end
    % waitbar will close via onCleanup if it still exists

    % Distances
    initialDistance = calculatePathDistance(path);

    % Post-processing
    k = min(100, numPoints);
    lastPointsStart = numPoints - k + 1;
    unoptimizedPoints = path(lastPointsStart:end, :);
    reorderedPath = reorderPoints(unoptimizedPoints);
    path(lastPointsStart:end, :) = reorderedPath;

    adjustedDistance = calculatePathDistance(path);
    delta = initialDistance - adjustedDistance;
    if delta ~= 0
        fprintf('Post processing algorithm saved %f µm of travel.\n', delta)
    end
end

function tf = isvalid_scalar(h)
    % Guard against [] and vector handles
    tf = ~isempty(h) && isgraphics(h) && isscalar(h) && isvalid(h);
end

function reordered = reorderPoints(points)
    n = size(points, 1);
    reordered = zeros(size(points));
    reordered(1, :) = points(1, :);
    remaining = points(2:end, :);
    for i = 2:n
        lastPoint = reordered(i-1, :);
        distances = vecnorm(remaining - lastPoint, 2, 2);
        [~, minIdx] = min(distances);
        reordered(i, :) = remaining(minIdx, :);
        remaining(minIdx, :) = [];
    end
end

function totalDistance = calculatePathDistance(path)
    totalDistance = sum(sqrt(sum(diff(path).^2, 2)));
end
