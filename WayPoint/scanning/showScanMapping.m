function showScanMapping(hWP, varargin)
%SHOWSCANMAPPING Visualize scan paths across tiles and Z layers.
%
% Designed as a visualize & debugging companion to startScanMapping().
% This function loops through the same tile/Z structure but
% only plots the paths instead of executing galvo playback.
%
% OPTIONS (Name-Value pairs)
%
%   'Animate'              true/false
%                          If true, draw each segment sequentially.
%                          If false, plot entire path immediately.
%
%   'ShowRelative'         true/false
%                          Plot galvo-space view (±500 µm).
%
%   'ShowAbsolute'         true/false
%                          Plot stage/world coordinates.
%
%   'Absolute3D'           true/false
%                          If true, plot absolute view in 3D.
%                          Default: true
%
%   'Buffer_um'            scalar
%                          Margin added around full bounds
%                          for absolute plotting.
%
%   'viewSamplingIndex'    positive integer
%                          Number of points per animation update.
%
%   'PlotDecimation'       positive integer
%                          Keep every Nth point for plotting only.
%                          Default: 1 (no decimation)
%
%   'AnimationDelay_s'     nonnegative scalar
%                          Pause after each animation update chunk.
%                          Default: 0
%
% Example
%
%   showScanMapping(hWP)
%
%   showScanMapping(hWP,...
%       'Animate',true,...
%       'ShowRelative',true,...
%       'ShowAbsolute',true,...
%       'Absolute3D',true)

%% ------------------------------------------------------------
% Parse inputs
%% ------------------------------------------------------------

p = inputParser;

addParameter(p,'Animate',true);
addParameter(p,'ShowRelative',false);
addParameter(p,'ShowAbsolute',true);
addParameter(p,'Absolute3D',true);
addParameter(p,'Buffer_um',100);
addParameter(p,'viewSamplingIndex',1000);
addParameter(p,'PlotDecimation',1);
addParameter(p,'AnimationDelay_s',0);


parse(p,varargin{:});
OPT = p.Results;

%% ------------------------------------------------------------
% Acquire stack + stage data
%% ------------------------------------------------------------

stack = hWP.hStacks;

scanPaths = stack.ScanPaths(:);
numTiles  = numel(scanPaths);
hasMeta = isprop(stack, 'ScanMeta') && ~isempty(stack.ScanMeta);

stagePath = hWP.aPath.Coordinates;

% Match startScanMapping() timing estimate parameters.
PDT_s = hWP.Settings.PixelDwellTime_ms / 1000;          % seconds
beamWaistDiameter_um = hWP.Settings.BeamWaistDiameter_um; % µm
rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um);
leadS = 0.004;
tailS = 0.002;

estimateScanMapTime(hWP);

%% ------------------------------------------------------------
% Determine global bounds (absolute view)
%% ------------------------------------------------------------

allX = [];
allY = [];
allZ = [];

for t = 1:numTiles
    
    if isempty(scanPaths{t})
        continue
    end
    
    tilePaths = scanPaths{t};
    
    for k = 1:numel(tilePaths)
        
        pth = tilePaths{k};
        
        if isempty(pth)
            continue
        end
        
        allX = [allX ; pth(:,1)];
        allY = [allY ; pth(:,2)];
        
    end
    
end

xmin = min(allX);
xmax = max(allX);
ymin = min(allY);
ymax = max(allY);

buf = OPT.Buffer_um;

xlim_abs = [xmin xmax] + [-buf buf];
ylim_abs = [ymin ymax] + [-buf buf];

%% ------------------------------------------------------------
% Create figures
%% ------------------------------------------------------------

if OPT.ShowRelative
    
    figRel = figure('Name','Galvo View (Relative)');
    axRel = axes(figRel);
    
    hold(axRel,'on')
    axis(axRel,'equal')
    
    xlim(axRel,[-500 500])
    ylim(axRel,[-500 500])
    
    xlabel(axRel,'X (µm)')
    ylabel(axRel,'Y (µm)')
    
end

if OPT.ShowAbsolute
    
    figAbs = figure('Name','Absolute Stage View');
    axAbs = axes(figAbs);
    
    hold(axAbs,'on')
    axis(axAbs,'equal')
    
    xlim(axAbs,xlim_abs)
    ylim(axAbs,ylim_abs)
    
    xlabel(axAbs,'X (µm)')
    ylabel(axAbs,'Y (µm)')
    
    if OPT.Absolute3D
        zlabel(axAbs,'Z (µm)')
        view(axAbs,3)
        set(axAbs, 'ZDir', 'reverse')

        camlight headlight
        lighting gouraud
        material dull
    end
    
end

%% ------------------------------------------------------------
% TILE LOOP
%% ------------------------------------------------------------

for tileIdx = 1:numTiles
    
    if isempty(scanPaths{tileIdx})
        fprintf('Tile %d empty\n',tileIdx)
        continue
    end
    
    fprintf('\nTile %d\n',tileIdx)
    
    tilePaths = scanPaths{tileIdx};
    
    if isrow(tilePaths)
        tilePaths = tilePaths.';
    end
    if hasMeta && numel(stack.ScanMeta) >= tileIdx && ~isempty(stack.ScanMeta{tileIdx})
        tileMeta = stack.ScanMeta{tileIdx};
        if isrow(tileMeta), tileMeta = tileMeta.'; end
    else
        tileMeta = cell(numel(tilePaths),1);
    end
    
    if ~isprop(stack,'ArbitraryZs')
        error('Stack has no ArbitraryZs.')
    end
    
    zLevels = stack.ArbitraryZs{tileIdx};
    
    if isempty(zLevels)
        continue
    end
    
    zLevels = zLevels(:);
    
    n = min([numel(tilePaths),numel(zLevels),numel(tileMeta)]);
    
    tilePaths = tilePaths(1:n);
    tileMeta  = tileMeta(1:n);
    zLevels   = zLevels(1:n);
    
    % Match startScanMapping() Z traversal behavior.
    switch hWP.Settings.ZTraversalMode
        case "ascending"
            [zLevels, order] = sort(zLevels, 'ascend');
        case "descending"
            [zLevels, order] = sort(zLevels, 'descend');
        otherwise
            error('Invalid ZTraversalMode.')
    end
    tilePaths = tilePaths(order);
    tileMeta = tileMeta(order);
    
    %% --------------------------------------------------------
    % Z LOOP
    %% --------------------------------------------------------
    
    for zIdx = 1:n
        
        rawPathXY = tilePaths{zIdx};
        
        if isempty(rawPathXY)
            continue
        end

        chunks = buildPlaybackChunks(rawPathXY, tileMeta{zIdx}, zLevels(zIdx), 1e-9);
        if isempty(chunks)
            continue
        end
        scanMask = ~[chunks.isTravel];
        scanChunks = chunks(scanMask);
        if isempty(scanChunks)
            continue
        end
        
        z = zLevels(zIdx) + hWP.hMask.Position(3);

        % Match startScanMapping() per-layer time estimate.
        totalLength_um = 0;
        for cIdx = 1:numel(chunks)
            xy = chunks(cIdx).xy;
            totalLength_um = totalLength_um + sum(hypot(diff(xy(:,1)), diff(xy(:,2))), 'omitnan');
        end
        estimatedTime_s = (totalLength_um / rasterSpacing_um) * PDT_s + numel(chunks) * (leadS + tailS);

        fprintf('  Z %d  (%.2f µm) | %.3f s\n', zIdx, z, estimatedTime_s)
        
        scanParts = arrayfun(@(c) c.xy, scanChunks, 'UniformOutput', false);
        [xAll, yAll] = buildPlotPath(scanParts, OPT.PlotDecimation);
        if numel(xAll) < 2
            continue
        end
        
        if OPT.ShowRelative
            cla(axRel)
            if OPT.Animate
                animateLine2D(axRel, xAll, yAll, 'b', OPT.viewSamplingIndex, OPT.AnimationDelay_s);
            else
                plot(axRel, xAll, yAll, 'b')
            end
        end
        
        if OPT.ShowAbsolute
            if OPT.Absolute3D
                zAll = ones(size(xAll)) * z;
                zAll(isnan(xAll) | isnan(yAll)) = nan;
                if OPT.Animate
                    animateLine3D(axAbs, xAll, yAll, zAll, 'k', OPT.viewSamplingIndex, OPT.AnimationDelay_s);
                else
                    plot3(axAbs, xAll, yAll, zAll, 'k')
                end
            else
                if OPT.Animate
                    animateLine2D(axAbs, xAll, yAll, 'k', OPT.viewSamplingIndex, OPT.AnimationDelay_s);
                else
                    plot(axAbs, xAll, yAll, 'k')
                end
            end
        end
        
    end
    
end

disp('Visualization complete.')

end


%% ------------------------------------------------------------------------
function [xAll, yAll] = buildPlotPath(subPaths, decimation)

xAll = [];
yAll = [];

if nargin < 2 || isempty(decimation) || decimation < 1
    decimation = 1;
end

for i = 1:numel(subPaths)
    sp = subPaths{i};
    if size(sp,1) < 2
        continue
    end
    
    if decimation > 1 && size(sp,1) > 2
        keepIdx = 1:decimation:size(sp,1);
        if keepIdx(end) ~= size(sp,1)
            keepIdx(end+1) = size(sp,1); %#ok<AGROW>
        end
        sp = sp(keepIdx,:);
    end
    
    xAll = [xAll; sp(:,1); nan]; %#ok<AGROW>
    yAll = [yAll; sp(:,2); nan]; %#ok<AGROW>
end

if ~isempty(xAll)
    xAll(end) = [];
    yAll(end) = [];
end

end


%% ------------------------------------------------------------------------
function animateLine2D(ax, x, y, color, chunkSize, delayS)

if nargin < 5 || isempty(chunkSize) || chunkSize < 2
    chunkSize = 20;
end
if nargin < 6 || isempty(delayS) || delayS < 0
    delayS = 0;
end

h = line(ax, nan, nan, 'Color', color);
N = numel(x);

for i = 1:chunkSize:N
    j = min(i + chunkSize - 1, N);
    set(h, 'XData', x(1:j), 'YData', y(1:j));
    drawnow limitrate nocallbacks
    if delayS > 0
        pause(delayS)
    end
end

end


%% ------------------------------------------------------------------------
function animateLine3D(ax, x, y, z, color, chunkSize, delayS)

if nargin < 6 || isempty(chunkSize) || chunkSize < 2
    chunkSize = 20;
end
if nargin < 7 || isempty(delayS) || delayS < 0
    delayS = 0;
end

h = line(ax, nan, nan, nan, 'Color', color);
N = numel(x);

for i = 1:chunkSize:N
    j = min(i + chunkSize - 1, N);
    set(h, 'XData', x(1:j), 'YData', y(1:j), 'ZData', z(1:j));
    drawnow limitrate nocallbacks
    if delayS > 0
        pause(delayS)
    end
end

end
