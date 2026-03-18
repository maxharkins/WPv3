function chunks = buildPlaybackChunks(pathPts, pathMeta, zBase_um, tol)
% buildPlaybackChunks
% Convert a layer path into ordered scan/travel XY chunks suitable for playback.
%
% INPUTS
%   pathPts  : [N x 2] XY, or [N x 3] XYZ primitives
%   pathMeta : [N x 1] optional travel flags (1=travel, 0=scan)
%   zBase_um : base layer Z (used when inferring travel from XYZ)
%   tol      : XY/Z tolerance (default 1e-9)
%
% OUTPUT
%   chunks(k).xy       [M x 2] XY chunk with consecutive duplicates removed
%   chunks(k).isTravel logical flag

    if nargin < 4 || isempty(tol)
        tol = 1e-9;
    end
    if nargin < 3 || isempty(zBase_um)
        zBase_um = NaN;
    end

    chunks = struct('xy', {}, 'isTravel', {});
    if isempty(pathPts) || size(pathPts,2) < 2 || size(pathPts,1) < 2
        return;
    end

    xy = pathPts(:,1:2);
    isBreak = any(~isfinite(xy), 2);

    if nargin >= 2 && ~isempty(pathMeta) && numel(pathMeta) == size(pathPts,1)
        isTravel = logical(pathMeta(:));
    elseif size(pathPts,2) >= 3 && isfinite(zBase_um)
        isTravel = abs(pathPts(:,3) - zBase_um) > tol;
    else
        isTravel = false(size(pathPts,1),1);
    end

    kind = -1 * ones(size(pathPts,1),1);  % -1 break, 0 scan, 1 travel
    kind(~isBreak & ~isTravel) = 0;
    kind(~isBreak &  isTravel) = 1;

    i = 1;
    while i <= numel(kind)
        while i <= numel(kind) && kind(i) < 0
            i = i + 1;
        end
        if i > numel(kind)
            break;
        end

        k = kind(i);
        j = i;
        while j + 1 <= numel(kind) && kind(j + 1) == k
            j = j + 1;
        end

        segXY = removeConsecutiveDuplicateXY(xy(i:j,:), tol);
        if size(segXY,1) >= 2
            chunks(end+1,1).xy = segXY; %#ok<AGROW>
            chunks(end,1).isTravel = logical(k);
        end

        i = j + 1;
    end
end

function out = removeConsecutiveDuplicateXY(in, tol)
    out = in;
    if size(in,1) < 2
        return;
    end
    keep = true(size(in,1),1);
    d = hypot(diff(in(:,1)), diff(in(:,2)));
    keep(2:end) = d > tol;
    out = in(keep,:);
end
