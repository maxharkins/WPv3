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
printImportAndPlanSummaryForShow(hWP);

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

allX = allX(isfinite(allX));
allY = allY(isfinite(allY));

if isempty(allX) || isempty(allY)
    xmin = -500;
    xmax = 500;
    ymin = -500;
    ymax = 500;
else
    xmin = min(allX);
    xmax = max(allX);
    ymin = min(allY);
    ymax = max(allY);
end

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

        nTravel = sum([chunks.isTravel]);
        nScan = numel(chunks) - nTravel;
        fprintf('  Z %d  (%.2f µm) | %.3f s | chunks: total=%d scan=%d travel=%d\n', ...
            zIdx, z, estimatedTime_s, numel(chunks), nScan, nTravel)
        
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

function printImportAndPlanSummaryForShow(hWP)
    stack = [];
    try
        stack = hWP.hStacks;
    catch
    end
    if isempty(stack)
        return;
    end

    if isprop(stack, 'LastImportStats') && isstruct(stack.LastImportStats) ...
            && isfield(stack.LastImportStats, 'source') && strcmpi(stack.LastImportStats.source, 'gcode')
        s = stack.LastImportStats;
        fprintf('[Import Stats] source=%s | moves=%d | extrusion=%d | travel=%d | travel-hops=%d\n', ...
            s.source, getStructInt(s, 'numMoves'), getStructInt(s, 'numExtrusionMoves'), ...
            getStructInt(s, 'numTravelMoves'), getStructInt(s, 'numTravelHopMoves'));
        fprintf('[Import Stats] length um: total=%.3f | extrusion=%.3f | travel=%.3f\n', ...
            getStructNum(s, 'totalLength_um'), getStructNum(s, 'extrusionLength_um'), getStructNum(s, 'travelLength_um'));
    end

    plan = summarizePlaybackPlanForShow(hWP);
    fprintf('[Show Plan] tiles=%d | layers=%d | chunks=%d (scan=%d, travel=%d)\n', ...
        plan.tiles, plan.layers, plan.totalChunks, plan.scanChunks, plan.travelChunks);
    fprintf('[Show Plan] length um: total=%.3f | scan=%.3f | travel=%.3f\n', ...
        plan.totalLength_um, plan.scanLength_um, plan.travelLength_um);
    fprintf('[Show Plan] estimate min: sample=%.3f | chunk-overhead=%.3f | total=%.3f\n', ...
        plan.sampleTime_min, plan.overheadTime_min, plan.estimatedTotal_min);
end

function out = summarizePlaybackPlanForShow(hWP)
    out = struct( ...
        'tiles', 0, ...
        'layers', 0, ...
        'totalChunks', 0, ...
        'scanChunks', 0, ...
        'travelChunks', 0, ...
        'totalLength_um', 0, ...
        'scanLength_um', 0, ...
        'travelLength_um', 0, ...
        'sampleTime_min', 0, ...
        'overheadTime_min', 0, ...
        'estimatedTotal_min', 0);

    stack = hWP.hStacks;
    if isempty(stack) || ~isprop(stack, 'ScanPaths') || isempty(stack.ScanPaths)
        return;
    end

    scanPaths = stack.ScanPaths(:);
    out.tiles = numel(scanPaths);
    hasMeta = isprop(stack, 'ScanMeta') && ~isempty(stack.ScanMeta);

    PDT_s = hWP.Settings.PixelDwellTime_ms / 1000;
    beamWaistDiameter_um = hWP.Settings.BeamWaistDiameter_um;
    rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um);
    leadS = 0.004;
    tailS = 0.002;

    for tileIdx = 1:numel(scanPaths)
        tilePaths = scanPaths{tileIdx};
        if isempty(tilePaths)
            continue;
        end
        if isrow(tilePaths), tilePaths = tilePaths.'; end

        if hasMeta && numel(stack.ScanMeta) >= tileIdx && ~isempty(stack.ScanMeta{tileIdx})
            tileMeta = stack.ScanMeta{tileIdx};
            if isrow(tileMeta), tileMeta = tileMeta.'; end
        else
            tileMeta = cell(numel(tilePaths), 1);
        end

        if ~isprop(stack, 'ArbitraryZs') || numel(stack.ArbitraryZs) < tileIdx || isempty(stack.ArbitraryZs{tileIdx})
            zLevels = zeros(numel(tilePaths), 1);
        else
            zLevels = stack.ArbitraryZs{tileIdx};
        end
        zLevels = zLevels(:);

        numZ = min([numel(tilePaths), numel(tileMeta), numel(zLevels)]);
        for zIdx = 1:numZ
            pathXY = tilePaths{zIdx};
            if isempty(pathXY) || size(pathXY,1) < 2
                continue;
            end

            chunks = buildPlaybackChunks(pathXY, tileMeta{zIdx}, zLevels(zIdx), 1e-9);
            if isempty(chunks)
                continue;
            end

            out.layers = out.layers + 1;
            for cIdx = 1:numel(chunks)
                seg = chunks(cIdx).xy;
                if size(seg,1) < 2
                    continue;
                end
                d = sum(hypot(diff(seg(:,1)), diff(seg(:,2))));
                out.totalChunks = out.totalChunks + 1;
                out.totalLength_um = out.totalLength_um + d;
                if chunks(cIdx).isTravel
                    out.travelChunks = out.travelChunks + 1;
                    out.travelLength_um = out.travelLength_um + d;
                else
                    out.scanChunks = out.scanChunks + 1;
                    out.scanLength_um = out.scanLength_um + d;
                end
            end
        end
    end

    sampleTime_s = (out.totalLength_um / rasterSpacing_um) * PDT_s;
    overhead_s = out.totalChunks * (leadS + tailS);
    out.sampleTime_min = sampleTime_s / 60;
    out.overheadTime_min = overhead_s / 60;
    out.estimatedTotal_min = (sampleTime_s + overhead_s) / 60;
end

function n = getStructNum(s, field)
    n = NaN;
    if isfield(s, field) && isnumeric(s.(field)) && isscalar(s.(field)) && isfinite(s.(field))
        n = double(s.(field));
    end
end

function n = getStructInt(s, field)
    n = 0;
    if isfield(s, field) && isnumeric(s.(field)) && isscalar(s.(field)) && isfinite(s.(field))
        n = round(double(s.(field)));
    end
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
