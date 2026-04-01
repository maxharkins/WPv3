
% strip config
center = [0,0]; % µm
width = 120; % µm
height = 20; % µm
spacing = 0.39; % µm
orientation = 'horizontal';
PDT_s = 1e-3; % seconds

beamWaistDiameter_um = 0.80; % µm
beam = hWP.hSI.hScan2D.hBeams{1}; % beam handle
[hX, hY] = getXYGalvos(hWP); % get galvo handles

leadS = 0; % s 
tailS = 0; % s

Pf = .25;

% Z config
zs = 200:-10:0; % µm

% image config
save_dir = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-03-31_surface-ablations\raw";
prefix = 'exp_004';

%% end of config

[x_um, y_um] = generateRasterStrip( ...
    center, width, height, spacing, orientation ...
    );

%convert to play paths
xy = [x_um(:),y_um(:)];
keep = [true; hypot(diff(xy(:,1)), diff(xy(:,2))) > 0];
xy = xy(keep,:);

x_play = xy(:,1);
y_play = xy(:,2);


figure
plot(x_um, y_um, '-')
xlim([-500, 500]),ylim([-500,500])
axis equal
pause(1)
disp('starting...')


for zIdx = 1:numel(zs)
    z = zs(zIdx);
    fprintf('starting #%d\n', zIdx)
    hWP.hSI.hMotors.moveSampleNoQuery([NaN, NaN, z], true); % move z
    
    pause(0.5)

% [stats, model] = playPreexistingPathUniform( ...
%     hX, hY, x_play, y_play, ...
%      PDT_s, ...
%     'BeamWaistDiameter_um', beamWaistDiameter_um, ...
%     'StartHold_s', 0, ...
%     'EndHold_s', 0, ...
%     'BeamHandle', beam, ...
%     'PowerFrac', Pf, ...
%     'TurnAngle_deg', 40, ...
%     'TurnBlank_s', 0.4e-3, ...
%     'SpeedPowerComp', true, ...
%     'AllowUnsyncedBeam', true);
tic
[stats, model] = playPreexistingPathSIStyle( ...
     hX, hY, ...
     x_play, y_play, ...
     PDT_s, ...
    'BeamWaistDiameter_um', beamWaistDiameter_um, ...
    'BeamHandle', beam, ...
    'PowerFrac', Pf, ...
    'BlankSharpTurns', true, ...
    'TurnBlank_s', 0.02e-3, ...
    'LeadIn_s', 0, 'TailOut_s', 0, ...
    'AllowUnsyncedBeam', true);
toc
% tic
%     playPreexistingPath(hX, hY, ...
%          x_play, y_play, ...
%          PDT_s, ...
%         'BeamWaistDiameter_um', beamWaistDiameter_um, ...
%         'BeamHandle', beam, ...
%         'PowerFrac', Pf, ...
%         'StartHold_s', leadS, ...
%         'EndHold_s', tailS, ...
%         'ParkWhenDone', false);
% toc
% return
    pause(0.5)

    grab_and_save_with_metadata(save_dir, 'Prefix', prefix);

    pause(0.5)

end





function [x_um, y_um] = generateRasterStrip(center, width, height, spacing, orientation)
% Generate continuous snaking raster path centered at (0,0) or given center
%
% center      = [x0, y0] (µm)
% width       = µm
% height      = µm
% spacing     = µm (line spacing)
% orientation = 'horizontal' or 'vertical' (primary line orientation)

x0 = center(1);
y0 = center(2);

x_min = x0 - width/2;
x_max = x0 + width/2;
y_min = y0 - height/2;
y_max = y0 + height/2;

x_um = [];
y_um = [];

hold_pts = 3; % turnaround dwell points

switch orientation

    case 'horizontal'
        y_lines = y_min:spacing:y_max;

        for i = 1:length(y_lines)
            y = y_lines(i);

            if mod(i,2)==1
                x_line = [x_min, x_max];
            else
                x_line = [x_max, x_min];
            end

            y_line = [y, y];

            % connect from previous segment
            if ~isempty(x_um)
                x_um = [x_um, x_line(1)];
                y_um = [y_um, y_line(1)];
            end

            % main line
            x_um = [x_um, x_line];
            y_um = [y_um, y_line];

            % turnaround dwell
            x_um = [x_um, repmat(x_line(end),1,hold_pts)];
            y_um = [y_um, repmat(y_line(end),1,hold_pts)];
        end

    case 'vertical'
        x_lines = x_min:spacing:x_max;

        for i = 1:length(x_lines)
            x = x_lines(i);

            if mod(i,2)==1
                y_line = [y_min, y_max];
            else
                y_line = [y_max, y_min];
            end

            x_line = [x, x];

            if ~isempty(x_um)
                x_um = [x_um, x_line(1)];
                y_um = [y_um, y_line(1)];
            end

            x_um = [x_um, x_line];
            y_um = [y_um, y_line];

            x_um = [x_um, repmat(x_line(end),1,hold_pts)];
            y_um = [y_um, repmat(y_line(end),1,hold_pts)];
        end
end
end


function [hX, hY] = getXYGalvos(hWP)
%GETXYGALVOS Try name-based lookup, then fallback indices 118/119.

    hX = [];
    hY = [];

    % Attempt name-based search in resource store (preferred)
    try
        rs = hWP.hSI.hResourceStore.hResources;
        for k = 1:numel(rs)
            r = rs{k};
            if isempty(r) || ~isobject(r), continue; end

            % Many ScanImage resources have a "name" property
            nm = '';
            try nm = string(r.name); catch, end

            if contains(lower(nm), "x galvo")
                hX = r;
            elseif contains(lower(nm), "y galvo")
                hY = r;
            end
        end
    catch
        % ignore and fall back below
    end

    % Fallback to your known indices if needed
    if isempty(hX) || isempty(hY)
        try
            rs = hWP.hSI.hResourceStore.hResources;
            if isempty(hX) && numel(rs) >= 118, hX = rs{118}; end
            if isempty(hY) && numel(rs) >= 119, hY = rs{119}; end
        catch
        end
    end
end