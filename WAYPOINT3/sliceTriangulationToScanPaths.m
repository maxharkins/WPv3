function layers = sliceTriangulationToScanPaths(triObj, cfg)
% sliceTriangulationToScanPaths
% Fast STL/triangulation slicer that returns ordered scan paths (edges-only)
% for each Z layer. Produces polyline paths from mesh-plane intersection,
% stitches segments into contours, resamples at XY resolution, and orders
% contours into a single continuous path per layer (minimizes jumps).
%
% INPUTS
%   triObj : triangulation OR struct with fields:
%              - Faces (Mx3)
%              - Vertices (Nx3)
%            OR [F,V] packed into a struct.
%
%   cfg : struct with fields (defaults shown):
%       cfg.xySpacing     = 1.0;     % units between points along contour
%       cfg.zStep         = 2.0;     % slice spacing in Z
%       cfg.zRange        = [];      % [zMin zMax]; empty => auto from mesh
%       cfg.zOffset       = 0.0;     % add to all z planes (optional)
%       cfg.tolXY         = 1e-6;    % tolerance for stitching endpoints
%       cfg.minSegLen     = 1e-9;    % drop tiny segments
%       cfg.closeTol      = 1e-5;    % consider contour closed if endpoints within this
%       cfg.keepOpen      = false;   % if true, keep open polylines too
%       cfg.orderMode     = "greedy";% "greedy" (default)
%       cfg.maxContours   = inf;     % optional limit per layer
%       cfg.verbose       = false;
%
% OUTPUT
%   layers : struct array with one element per Z plane:
%       layers(k).z       : Z value
%       layers(k).paths   : cell array of paths, each Nx3 [x y z]
%       layers(k).path    : single concatenated path Nx3 (NaN breaks) (optional convenience)
%       layers(k).contours: cell array of raw stitched contours (XY)
%
% NOTES
%   - Edges-only: you get intersection contours, not filled raster.
%   - Works best for watertight meshes. Non-manifold meshes may create open contours.
%   - For speed, intersection is fully vectorized over triangles; stitching is the heavier part.
%
% EXAMPLE
%   T = triangulation(F,V);
%   cfg.xySpacing = 0.8;
%   cfg.zStep     = 5;
%   layers = sliceTriangulationToScanPaths(T, cfg);
%   plot(layers(10).path(:,1), layers(10).path(:,2), '.-'); axis equal;

%% -------------------- Parse inputs --------------------
[F, V] = local_getFV(triObj);

cfg = local_applyDefaults(cfg);

zMinMesh = min(V(:,3));
zMaxMesh = max(V(:,3));

if isempty(cfg.zRange)
    zMin = zMinMesh;
    zMax = zMaxMesh;
else
    zMin = cfg.zRange(1);
    zMax = cfg.zRange(2);
end

% Define slice planes (inclusive)
zPlanes = (zMin:cfg.zStep:zMax) + cfg.zOffset;
nZ = numel(zPlanes);

layers = repmat(struct('z',[],'paths',{{}},'path',[],'contours',{{}}), nZ, 1);

if cfg.verbose
    fprintf('Slicing %d planes (zStep=%.6g, xySpacing=%.6g)\n', nZ, cfg.zStep, cfg.xySpacing);
end

%% -------------------- Slice loop --------------------
for k = 1:nZ
    z0 = zPlanes(k);

    % 1) Intersect mesh with z=z0 -> segments [x1 y1 x2 y2]
    segs = local_sliceZ_segments(F, V, z0, cfg.minSegLen);

    % 2) Stitch segments into contours (cell array of Nx2)
    contours = local_stitchSegments(segs, cfg.tolXY, cfg.closeTol, cfg.keepOpen);

    % Optional limit
    if numel(contours) > cfg.maxContours
        contours = contours(1:cfg.maxContours);
    end

    % 3) Resample contours at xySpacing
    resampled = cell(0,1);
    for c = 1:numel(contours)
        poly = contours{c};
        if size(poly,1) < 2
            continue
        end
        pts = local_resamplePolyline(poly, cfg.xySpacing);
        if ~isempty(pts)
            resampled{end+1,1} = pts; %#ok<AGROW>
        end
    end

    % 4) Order contours into scan path(s)
    pathsXY = local_orderContours(resampled, cfg.orderMode);

    % 5) Attach Z, build outputs
    pathsXYZ = cell(size(pathsXY));
    for i = 1:numel(pathsXY)
        xy = pathsXY{i};
        pathsXYZ{i} = [xy, repmat(z0, size(xy,1), 1)];
    end

    layers(k).z = z0;
    layers(k).paths = pathsXYZ;
    layers(k).contours = contours;

    % Convenience: concatenated path with NaN separators between contours
    layers(k).path = local_concatWithNaNs(pathsXYZ);

    if cfg.verbose
        fprintf('z=%.6g: %d segs -> %d contours -> %d paths\n', z0, size(segs,1), numel(contours), numel(pathsXYZ));
    end
end

end

%% ========================================================================
%                               Helpers
% ========================================================================

function cfg = local_applyDefaults(cfg)
if nargin < 1 || isempty(cfg), cfg = struct(); end

cfg = local_def(cfg, 'xySpacing', 1.0);
cfg = local_def(cfg, 'zStep',     2.0);
cfg = local_def(cfg, 'zRange',    []);
cfg = local_def(cfg, 'zOffset',   0.0);

cfg = local_def(cfg, 'tolXY',     1e-6);
cfg = local_def(cfg, 'minSegLen', 1e-9);
cfg = local_def(cfg, 'closeTol',  1e-5);

cfg = local_def(cfg, 'keepOpen',  false);
cfg = local_def(cfg, 'orderMode', "greedy");
cfg = local_def(cfg, 'maxContours', inf);
cfg = local_def(cfg, 'verbose',   false);

% sanity
cfg.xySpacing = double(cfg.xySpacing);
cfg.zStep     = double(cfg.zStep);
cfg.tolXY     = double(cfg.tolXY);
cfg.minSegLen = double(cfg.minSegLen);
cfg.closeTol  = double(cfg.closeTol);
end

function cfg = local_def(cfg, name, val)
if ~isfield(cfg, name) || isempty(cfg.(name))
    cfg.(name) = val;
end
end

function [F, V] = local_getFV(triObj)
if isa(triObj, 'triangulation')
    F = triObj.ConnectivityList;
    V = triObj.Points;
elseif isstruct(triObj) && isfield(triObj,'Faces') && isfield(triObj,'Vertices')
    F = triObj.Faces;
    V = triObj.Vertices;
elseif isstruct(triObj) && isfield(triObj,'ConnectivityList') && isfield(triObj,'Points')
    F = triObj.ConnectivityList;
    V = triObj.Points;
else
    error('triObj must be triangulation or struct with Faces/Vertices.');
end

F = double(F);
V = double(V);

if size(V,2) ~= 3
    error('Vertices must be Nx3.');
end
if size(F,2) ~= 3
    error('Faces must be Mx3.');
end
end

function segs = local_sliceZ_segments(F, V, z0, minSegLen)
% Vectorized mesh-plane intersection for z=z0.
% Returns segments as Ns x 4: [x1 y1 x2 y2]

M = size(F,1);

Vf = V(F(:),:);              % (3M) x 3
Vf = reshape(Vf, M, 3, 3);   % M x 3(verts) x 3(coords)

Z = Vf(:,:,3) - z0;          % signed distances (M x 3)
S = Z > 0;

% Triangles that cross plane (one or two vertices above)
sumS = sum(S,2);
crossTri = (sumS == 1) | (sumS == 2);

if ~any(crossTri)
    segs = zeros(0,4);
    return
end

Vf = Vf(crossTri,:,:);
Z  = Z(crossTri,:);
S  = S(crossTri,:);

% Determine intersection points on crossing edges
edges = [1 2; 2 3; 3 1];

% Accumulate all intersection points (each crossing edge gives one point)
Pxy_all = zeros(0,2);
triId_all = zeros(0,1); % to pair points by triangle

for e = 1:3
    i = edges(e,1);
    j = edges(e,2);

    crossEdge = xor(S(:,i), S(:,j));
    if ~any(crossEdge), continue; end

    Zi = Z(crossEdge,i);
    Zj = Z(crossEdge,j);
    t  = Zi ./ (Zi - Zj);  % in [0,1]

    Pi = Vf(crossEdge,i,:);
    Pj = Vf(crossEdge,j,:);

    P  = Pi + t .* (Pj - Pi);  % K x 1 x 3
    P  = squeeze(P(:,1:2));    % K x 2

    Pxy_all = [Pxy_all; P]; %#ok<AGROW>

    % map these intersections back to "crossing triangle index"
    triIdx = find(crossTri);
    triIdx = triIdx(:);
    triIdx = triIdx(sumS(crossTri) == sumS(crossTri)); %#ok<NASGU> % no-op, keep size stable

    % We need triangle ids for current filtered set; easiest:
    % Create ids for filtered triangles once outside loop (below)
end

% The above triId_all is not yet built; do it properly:
% Recompute per-edge but track local triangle indices (1..numCrossTris)
nCross = size(Vf,1);
Pxy_all = zeros(0,2);
triId_all = zeros(0,1);

for e = 1:3
    i = edges(e,1);
    j = edges(e,2);

    crossEdge = xor(S(:,i), S(:,j));
    if ~any(crossEdge), continue; end

    Zi = Z(crossEdge,i);
    Zj = Z(crossEdge,j);
    t  = Zi ./ (Zi - Zj);

    Pi = Vf(crossEdge,i,:);
    Pj = Vf(crossEdge,j,:);

    P  = Pi + t .* (Pj - Pi);
    P  = squeeze(P(:,1:2));

    Pxy_all = [Pxy_all; P]; %#ok<AGROW>
    triId_all = [triId_all; find(crossEdge)]; %#ok<AGROW>
end

% Each crossing triangle should contribute exactly 2 intersection points
% (ignoring coplanar degeneracies). We will group and pair.
if isempty(Pxy_all)
    segs = zeros(0,4);
    return
end

% Group by triangle id
[triSorted, ord] = sort(triId_all);
Pxy_sorted = Pxy_all(ord,:);

% Count occurrences per tri
[triUniq, firstIdx, ~] = unique(triSorted, 'stable');
counts = diff([firstIdx; numel(triSorted)+1]);

% Keep only triangles with exactly 2 intersection points
keep = (counts == 2);
if ~any(keep)
    segs = zeros(0,4);
    return
end

triKeep = triUniq(keep);
% Build segments
segs = zeros(numel(triKeep), 4);
out = 0;

cursor = 1;
for u = 1:numel(triUniq)
    c = counts(u);
    if keep(u)
        p1 = Pxy_sorted(cursor,   :);
        p2 = Pxy_sorted(cursor+1, :);
        out = out + 1;
        segs(out,:) = [p1 p2];
    end
    cursor = cursor + c;
end

% Remove tiny segments
dx = segs(:,1) - segs(:,3);
dy = segs(:,2) - segs(:,4);
len = hypot(dx,dy);
segs = segs(len > minSegLen, :);

end

function contours = local_stitchSegments(segs, tolXY, closeTol, keepOpen)
% Stitch unordered segments into polylines.
% segs: Ns x 4 [x1 y1 x2 y2]
% Returns: cell array, each element Nx2 polyline (closed if loop)

if isempty(segs)
    contours = cell(0,1);
    return
end

p1 = segs(:,1:2);
p2 = segs(:,3:4);

% Quantize points to tolerance grid for stable matching
q1 = round(p1 / tolXY);
q2 = round(p2 / tolXY);

% Build integer keys for endpoints using shifted packing
qx = [q1(:,1); q2(:,1)];
qy = [q1(:,2); q2(:,2)];

minX = min(qx); minY = min(qy);
qxS = int64(qx - minX);
qyS = int64(qy - minY);
stride = uint64(max(qyS) + 1);

keys = uint64(qxS) .* stride + uint64(qyS); % 2Ns keys

% Endpoint index encoding:
% endpointIdx = 1..Ns for p1, Ns+1..2Ns for p2
Ns = size(segs,1);
epIdx = (1:(2*Ns)).';

% Build adjacency map: key -> list of endpoint indices
adj = containers.Map('KeyType','uint64','ValueType','any');
for i = 1:numel(keys)
    k = keys(i);
    if isKey(adj, k)
        adj(k) = [adj(k); epIdx(i)];
    else
        adj(k) = epIdx(i);
    end
end

used = false(Ns,1);
contours = cell(0,1);

for s = 1:Ns
    if used(s), continue; end

    % Start with segment s, direction from p1->p2
    used(s) = true;
    poly = [p1(s,:); p2(s,:)];

    % Extend forward (at end)
    poly = local_extend(poly, +1, s);

    % Extend backward (at start)
    poly = local_extend(poly, -1, s);

    % Decide if closed
    if hypot(poly(1,1)-poly(end,1), poly(1,2)-poly(end,2)) <= closeTol
        % Force closure by exact equality of endpoints
        poly(end,:) = poly(1,:);
        contours{end+1,1} = poly; %#ok<AGROW>
    else
        if keepOpen
            contours{end+1,1} = poly; %#ok<AGROW>
        end
    end
end

    function poly2 = local_extend(polyIn, dirSign, segStart)
        poly2 = polyIn;

        while true
            if dirSign > 0
                currPt = poly2(end,:);
            else
                currPt = poly2(1,:);
            end

            q = round(currPt / tolXY);
            qxC = int64(q(1) - minX);
            qyC = int64(q(2) - minY);
            keyC = uint64(qxC) * stride + uint64(qyC);

            if ~isKey(adj, keyC)
                break
            end

            candidates = adj(keyC); % endpoint indices connected to currPt

            % Choose an unused segment that connects here
            nextSeg = 0;
            nextEnd = 0;
            for t = 1:numel(candidates)
                eIdx = candidates(t);
                if eIdx <= Ns
                    segIdx = eIdx;
                    endId = 1; % p1
                else
                    segIdx = eIdx - Ns;
                    endId = 2; % p2
                end
                if used(segIdx)
                    continue
                end
                nextSeg = segIdx;
                nextEnd = endId;
                break
            end

            if nextSeg == 0
                break
            end

            used(nextSeg) = true;

            % Append the other endpoint of nextSeg
            if nextEnd == 1
                otherPt = p2(nextSeg,:);
            else
                otherPt = p1(nextSeg,:);
            end

            if dirSign > 0
                poly2 = [poly2; otherPt]; %#ok<AGROW>
            else
                poly2 = [otherPt; poly2]; %#ok<AGROW>
            end
        end
    end

end

function pts = local_resamplePolyline(poly, spacing)
% Resample polyline at approximately uniform arc-length spacing.
% For closed polylines, assumes last point equals first point.

if size(poly,1) < 2 || spacing <= 0
    pts = poly;
    return
end

% Remove consecutive duplicates
d0 = hypot(diff(poly(:,1)), diff(poly(:,2)));
keep = [true; d0 > 0];
poly = poly(keep,:);
if size(poly,1) < 2
    pts = poly;
    return
end

isClosed = hypot(poly(1,1)-poly(end,1), poly(1,2)-poly(end,2)) < 1e-12;

% Arc-length
d = hypot(diff(poly(:,1)), diff(poly(:,2)));
s = [0; cumsum(d)];
L = s(end);

if L < spacing
    pts = poly;
    return
end

sQuery = (0:spacing:L).';
x = interp1(s, poly(:,1), sQuery, 'linear');
y = interp1(s, poly(:,2), sQuery, 'linear');
pts = [x y];

% If closed, drop final point if it duplicates the first
if isClosed && size(pts,1) > 1
    if hypot(pts(1,1)-pts(end,1), pts(1,2)-pts(end,2)) < 1e-12
        pts(end,:) = [];
    end
end

end

function paths = local_orderContours(contours, mode)
% Order multiple contours to minimize travel jumps.
% Returns cell array of ordered polylines (each Nx2).
% "greedy" chooses next contour whose closest point is nearest to current end.

if isempty(contours)
    paths = cell(0,1);
    return
end

mode = string(mode);
if mode ~= "greedy"
    mode = "greedy";
end

% Sort contours by length descending (start from biggest)
n = numel(contours);
lens = zeros(n,1);
for i = 1:n
    c = contours{i};
    d = hypot(diff(c(:,1)), diff(c(:,2)));
    lens(i) = sum(d);
end
[~, ord] = sort(lens, 'descend');
contours = contours(ord);

used = false(n,1);
paths = cell(0,1);

% Start with the largest
curr = contours{1};
used(1) = true;
paths{end+1,1} = curr; %#ok<AGROW>
currEnd = curr(end,:);

for k = 2:n
    bestIdx = 0;
    bestCost = inf;
    bestPoly = [];

    for i = 1:n
        if used(i), continue; end
        poly = contours{i};
        if isempty(poly) || size(poly,1) < 2, continue; end

        % Allow rotation for closed loops: start at closest vertex to currEnd
        polyAdj = local_reanchor(poly, currEnd);

        % Choose direction to minimize start jump
        dStart = hypot(polyAdj(1,1)-currEnd(1), polyAdj(1,2)-currEnd(2));
        dEnd   = hypot(polyAdj(end,1)-currEnd(1), polyAdj(end,2)-currEnd(2));

        if dEnd < dStart
            polyAdj = flipud(polyAdj);
            cost = dEnd;
        else
            cost = dStart;
        end

        if cost < bestCost
            bestCost = cost;
            bestIdx = i;
            bestPoly = polyAdj;
        end
    end

    if bestIdx == 0
        break
    end

    used(bestIdx) = true;
    paths{end+1,1} = bestPoly; %#ok<AGROW>
    currEnd = bestPoly(end,:);
end

end

function polyOut = local_reanchor(poly, refPt)
% If closed-like, rotate polyline so its first point is closest to refPt.
% For open polylines, returns unchanged.

if size(poly,1) < 3
    polyOut = poly;
    return
end

isClosed = hypot(poly(1,1)-poly(end,1), poly(1,2)-poly(end,2)) < 1e-9;
if ~isClosed
    polyOut = poly;
    return
end

% Remove duplicate last point for rotation logic
polyCore = poly(1:end-1,:);

d = hypot(polyCore(:,1)-refPt(1), polyCore(:,2)-refPt(2));
[~, idx] = min(d);

polyOut = [polyCore(idx:end,:); polyCore(1:idx-1,:); polyCore(idx,:)]; % re-close

end

function P = local_concatWithNaNs(pathsXYZ)
% Concatenate cell array of Nx3 paths into one Nx3 with NaN separators.
if isempty(pathsXYZ)
    P = zeros(0,3);
    return
end
P = zeros(0,3);
for i = 1:numel(pathsXYZ)
    p = pathsXYZ{i};
    if isempty(p), continue; end
    if ~isempty(P)
        P = [P; [NaN NaN NaN]]; %#ok<AGROW>
    end
    P = [P; p]; %#ok<AGROW>
end
end