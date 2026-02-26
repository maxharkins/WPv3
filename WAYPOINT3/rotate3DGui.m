function [coordsOut, didApply, Rfinal] = rotate3DGui(coordsIn, varargin)
% rotate3DGui 2:01
% Simple interactive orientation helper for Nx3 coordinates (points/vertices).
%
% Usage:
%   [coordsRot, didApply, R] = rotate3DGui(coords, 'Title', 'Rotate STL');
%
% Inputs:
%   coordsIn : Nx3 double
%
% Name-Value:
%   'Title'            : window title (default "Rotate 3D Geometry")
%   'PointSize'        : scatter point size (default 8)
%   'UseScatter'       : true=render as scatter3, false=render as trisurf if faces provided (default true)
%   'Faces'            : Mx3 triangulation (optional). If provided, uses patch/trisurf view.
%   'ShowAxesTriad'    : true/false (default true)
%
% Outputs:
%   coordsOut : rotated coordinates (same size as input)
%   didApply  : logical, true if user hit Apply, false if Cancel/closed
%   Rfinal    : 3x3 rotation matrix applied (about origin)
%
% Notes:
% - Rotation is applied about the origin (0,0,0). If you want to rotate about centroid,
%   center first, rotate, then uncenter.
%
% Max Harkins style: robust, minimal assumptions, GUI is optional.

% ---------------------------
% Parse inputs
% ---------------------------
p = inputParser;
p.addRequired('coordsIn', @(x) isnumeric(x) && ismatrix(x) && size(x,2) == 3);
p.addParameter('Title', 'Rotate 3D Geometry', @(s) ischar(s) || isstring(s));
p.addParameter('PointSize', 8, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('UseScatter', true, @(x) islogical(x) && isscalar(x));
p.addParameter('Faces', [], @(x) isempty(x) || (isnumeric(x) && size(x,2) == 3));
p.addParameter('ShowAxesTriad', true, @(x) islogical(x) && isscalar(x));
p.parse(coordsIn, varargin{:});

coordsIn = double(coordsIn);
faces    = p.Results.Faces;

coordsOut = coordsIn;
didApply  = false;
Rfinal    = eye(3);

% ---------------------------
% Create UI
% ---------------------------
fig = uifigure('Name', char(p.Results.Title), 'Position', [100 100 1050 650], ...
              'CloseRequestFcn', @onCancel);

% Layout: left plot, right controls
gl = uigridlayout(fig, [1 2]);
gl.ColumnWidth = {'1x', 320};
gl.RowHeight   = {'1x'};

% Axes (use uiaxes)
ax = uiaxes(gl);
ax.Box = 'on';
ax.DataAspectRatio = [1 1 1];
grid(ax, 'on');
xlabel(ax,'X'); ylabel(ax,'Y'); zlabel(ax,'Z');
title(ax,'Rotate with sliders or +/-90 buttons. Apply to accept.');
set(ax, "Projection", "perspective")
ax.ZDir = 'reverse';
assignin("base", "ax3D", ax)

% Controls panel
panel = uipanel(gl, 'Title', 'Rotation Controls');
pg = uigridlayout(panel, [14 3]);
pg.RowHeight = {22,22,22,22,22,22,22,22,22,22,22,'1x',32,32};
pg.ColumnWidth = {80,'1x',80};

% Internal state (degrees)
state.axDeg = 0;
state.ayDeg = 0;
state.azDeg = 0;

% Render handles
hGeom = [];
hTriad = [];

% ---------------------------
% Draw initial geometry
% ---------------------------
renderGeometry();
updateTriad();

% ---------------------------
% Controls: sliders + numeric readouts
% ---------------------------
%% =========================
% X ROTATION
% =========================
lblX = uilabel(pg, ...
    'Text', 'Rot X (deg)', ...
    'HorizontalAlignment', 'left');
lblX.Layout.Row = 1;
lblX.Layout.Column = 1;

sx = uislider(pg, ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangingFcn', @(s,e) onSliderChanging('x', e.Value), ...
    'ValueChangedFcn',  @(s,e) onSliderChanged('x', e.Value));
sx.Layout.Row = 1;
sx.Layout.Column = 2;

nx = uieditfield(pg, 'numeric', ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangedFcn', @(s,e) onNumericChanged('x', s.Value));
nx.Layout.Row = 1;
nx.Layout.Column = 3;


%% =========================
% Y ROTATION
% =========================
lblY = uilabel(pg, ...
    'Text', 'Rot Y (deg)', ...
    'HorizontalAlignment', 'left');
lblY.Layout.Row = 2;
lblY.Layout.Column = 1;

sy = uislider(pg, ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangingFcn', @(s,e) onSliderChanging('y', e.Value), ...
    'ValueChangedFcn',  @(s,e) onSliderChanged('y', e.Value));
sy.Layout.Row = 2;
sy.Layout.Column = 2;

ny = uieditfield(pg, 'numeric', ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangedFcn', @(s,e) onNumericChanged('y', s.Value));
ny.Layout.Row = 2;
ny.Layout.Column = 3;


%% =========================
% Z ROTATION
% =========================
lblZ = uilabel(pg, ...
    'Text', 'Rot Z (deg)', ...
    'HorizontalAlignment', 'left');
lblZ.Layout.Row = 3;
lblZ.Layout.Column = 1;

sz = uislider(pg, ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangingFcn', @(s,e) onSliderChanging('z', e.Value), ...
    'ValueChangedFcn',  @(s,e) onSliderChanged('z', e.Value));
sz.Layout.Row = 3;
sz.Layout.Column = 2;

nz = uieditfield(pg, 'numeric', ...
    'Limits', [-180 180], ...
    'Value', 0, ...
    'ValueChangedFcn', @(s,e) onNumericChanged('z', s.Value));
nz.Layout.Row = 3;
nz.Layout.Column = 3;
%% =========================
% ORTHOGONAL ROTATION BUTTONS
% =========================
lblOrth = uilabel(pg, ...
    'Text', 'Orthogonal', ...
    'FontWeight', 'bold');
lblOrth.Layout.Row = 5;
lblOrth.Layout.Column = 1;

btnXn = uibutton(pg, 'Text', 'X -90', ...
    'ButtonPushedFcn', @(s,e) bump('x', -90));
btnXn.Layout.Row = 6;
btnXn.Layout.Column = 1;

btnXp = uibutton(pg, 'Text', 'X +90', ...
    'ButtonPushedFcn', @(s,e) bump('x', +90));
btnXp.Layout.Row = 6;
btnXp.Layout.Column = 3;

btnYn = uibutton(pg, 'Text', 'Y -90', ...
    'ButtonPushedFcn', @(s,e) bump('y', -90));
btnYn.Layout.Row = 7;
btnYn.Layout.Column = 1;

btnYp = uibutton(pg, 'Text', 'Y +90', ...
    'ButtonPushedFcn', @(s,e) bump('y', +90));
btnYp.Layout.Row = 7;
btnYp.Layout.Column = 3;

btnZn = uibutton(pg, 'Text', 'Z -90', ...
    'ButtonPushedFcn', @(s,e) bump('z', -90));
btnZn.Layout.Row = 8;
btnZn.Layout.Column = 1;

btnZp = uibutton(pg, 'Text', 'Z +90', ...
    'ButtonPushedFcn', @(s,e) bump('z', +90));
btnZp.Layout.Row = 8;
btnZp.Layout.Column = 3;

%% =========================
% VIEW CONTROLS
% =========================
lblView = uilabel(pg, ...
    'Text', 'View', ...
    'FontWeight', 'bold');
lblView.Layout.Row = 10;
lblView.Layout.Column = 1;

btnTop = uibutton(pg, ...
    'Text', 'XY (Top)', ...
    'ButtonPushedFcn', @(s,e) view(ax, 0, 90));
btnTop.Layout.Row = 10;
btnTop.Layout.Column = 2;

btnFront = uibutton(pg, ...
    'Text', 'XZ (Front)', ...
    'ButtonPushedFcn', @(s,e) view(ax, 0, 0));
btnFront.Layout.Row = 11;
btnFront.Layout.Column = 2;

btnSide = uibutton(pg, ...
    'Text', 'YZ (Side)', ...
    'ButtonPushedFcn', @(s,e) view(ax, 90, 0));
btnSide.Layout.Row = 12;
btnSide.Layout.Column = 2;

btnReset = uibutton(pg, ...
    'Text', 'Reset Rot', ...
    'ButtonPushedFcn', @(s,e) resetRot());
btnReset.Layout.Row = 11;
btnReset.Layout.Column = 1;
%% =========================
% APPLY / CANCEL
% =========================
applyBtn = uibutton(pg, ...
    'Text', 'Apply', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @onApply);
applyBtn.Layout.Row = 13;
applyBtn.Layout.Column = [1 3];

cancelBtn = uibutton(pg, ...
    'Text', 'Cancel', ...
    'ButtonPushedFcn', @onCancel);
cancelBtn.Layout.Row = 14;
cancelBtn.Layout.Column = [1 3];

% Wait for UI
uiwait(fig);

% ---------------------------
% Nested callbacks
% ---------------------------
    function onSliderChanging(axisChar, v)
        setAxisDeg(axisChar, v);
        syncControls(axisChar, v, true);
        rerender();
    end

    function onSliderChanged(axisChar, v)
        setAxisDeg(axisChar, v);
        syncControls(axisChar, v, false);
        rerender();
    end

    function onNumericChanged(axisChar, v)
        setAxisDeg(axisChar, v);
        syncAllControls();
        rerender();
    end

    function bump(axisChar, dv)
        v = getAxisDeg(axisChar) + dv;
        % wrap to [-180,180] to keep sliders happy
        v = wrapTo180(v);
        setAxisDeg(axisChar, v);
        syncAllControls();
        rerender();
    end

    function resetRot()
        state.axDeg = 0; state.ayDeg = 0; state.azDeg = 0;
        syncAllControls();
        rerender();
    end

    function rerender()
    
        % --- Save camera state ---
        camState.Position  = campos(ax);
        camState.Target    = camtarget(ax);
        camState.UpVector  = camup(ax);
        camState.ViewAngle = camva(ax);
    
        % --- Apply rotation ---
        coordsOut = applyRotation(coordsIn, ...
            state.axDeg, ...
            state.ayDeg, ...
            state.azDeg);
    
        Rfinal = rotationMatrixXYZ( ...
            state.axDeg, ...
            state.ayDeg, ...
            state.azDeg);
    
        % --- Update geometry only ---
        updateGeometry(coordsOut);
    
        % --- Restore camera ---
        campos(ax, camState.Position);
        camtarget(ax, camState.Target);
        camup(ax, camState.UpVector);
        camva(ax, camState.ViewAngle);
    
        drawnow limitrate;
    end

    function onApply(~,~)
        didApply = true;
        coordsOut = applyRotation(coordsIn, state.axDeg, state.ayDeg, state.azDeg);
        Rfinal    = rotationMatrixXYZ(state.axDeg, state.ayDeg, state.azDeg);
        uiresume(fig);
        delete(fig);
    end

    function onCancel(~,~)
        didApply = false;
        coordsOut = coordsIn;
        Rfinal    = eye(3);
        if isvalid(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function setAxisDeg(axisChar, v)
        v = max(-180, min(180, double(v)));
        switch lower(axisChar)
            case 'x', state.axDeg = v;
            case 'y', state.ayDeg = v;
            case 'z', state.azDeg = v;
        end
    end

    function v = getAxisDeg(axisChar)
        switch lower(axisChar)
            case 'x', v = state.axDeg;
            case 'y', v = state.ayDeg;
            case 'z', v = state.azDeg;
        end
    end

    function syncControls(axisChar, v, isChanging)
        % Keep paired slider/numeric consistent; only update the one not moving.
        v = double(v);
        switch lower(axisChar)
            case 'x'
                if ~isChanging, sx.Value = v; end
                nx.Value = v;
            case 'y'
                if ~isChanging, sy.Value = v; end
                ny.Value = v;
            case 'z'
                if ~isChanging, sz.Value = v; end
                nz.Value = v;
        end
    end

    function syncAllControls()
        sx.Value = state.axDeg; nx.Value = state.axDeg;
        sy.Value = state.ayDeg; ny.Value = state.ayDeg;
        sz.Value = state.azDeg; nz.Value = state.azDeg;
    end

    function renderGeometry()

        cla(ax);
    
        if ~isempty(faces) && ~p.Results.UseScatter
    
            hGeom = patch(ax, ...
                'Vertices', coordsOut, ...
                'Faces', faces, ...
                'FaceColor', [0.85 0.85 0.88], ...
                'EdgeColor', 'none', ...
                'FaceLighting', 'gouraud', ...
                'AmbientStrength', 0.3, ...
                'DiffuseStrength', 0.8, ...
                'SpecularStrength', 0.2, ...
                'SpecularExponent', 25);
    
            material(ax, 'dull');
            camlight(ax, 'headlight');
            camlight(ax, 'right');
    
        else
            warning("YHOO")
            hGeom = scatter3(ax, ...
                coordsOut(:,1), ...
                coordsOut(:,2), ...
                coordsOut(:,3), ...
                p.Results.PointSize, ...
                'filled');
        end
    
        axis(ax,'equal');
        rotate3d(ax,'on');
    
        % Fix limits
        r = max(vecnorm(coordsOut,2,2));
        R = 1.05 * r;
        xlim(ax, [-R R]);
        ylim(ax, [-R R]);
        zlim(ax, [-R R]);
        axis(ax,'manual');
    
    end
    function updateGeometry(c)
        if isempty(hGeom) || ~isvalid(hGeom)
            coordsOut = c;
            renderGeometry();
            return;
        end

        if isa(hGeom, 'matlab.graphics.chart.primitive.Scatter')
            hGeom.XData = c(:,1);
            hGeom.YData = c(:,2);
            hGeom.ZData = c(:,3);
        else
            % patch
            hGeom.Vertices = c;
        end

        %axis(ax, 'equal');
    end

    function updateTriad()
        if ~p.Results.ShowAxesTriad
            if ~isempty(hTriad) && all(isvalid(hTriad)), delete(hTriad); end
            hTriad = [];
            return;
        end

        % delete previous
        if ~isempty(hTriad)
            try
                delete(hTriad(isvalid(hTriad)));
            catch
            end
        end

        % Draw a small triad at origin in current rotated frame
        % Choose length based on data scale
        spans = max(coordsOut,[],1) - min(coordsOut,[],1);
        L = 0.15 * max(spans);
        if ~(isfinite(L) && L > 0)
            L = 1;
        end

        % Use rotated basis
        R = rotationMatrixXYZ(state.axDeg, state.ayDeg, state.azDeg);
        ex = (R*[L;0;0])';
        ey = (R*[0;L;0])';
        ez = (R*[0;0;L])';

        hold(ax,'on');
        hTriad(1) = plot3(ax, [0 ex(1)], [0 ex(2)], [0 ex(3)], 'r-', 'LineWidth', 2);
        hTriad(2) = plot3(ax, [0 ey(1)], [0 ey(2)], [0 ey(3)], 'g-', 'LineWidth', 2);
        hTriad(3) = plot3(ax, [0 ez(1)], [0 ez(2)], [0 ez(3)], 'b-', 'LineWidth', 2);
        hold(ax,'off');
    end

end % main function

% ---------------------------
% Local helpers
% ---------------------------
function cRot = applyRotation(c, axDeg, ayDeg, azDeg)
R = rotationMatrixXYZ(axDeg, ayDeg, azDeg);
cRot = (R * c')';
end

function R = rotationMatrixXYZ(axDeg, ayDeg, azDeg)
% Extrinsic rotations about FIXED global X, Y, Z axes
% Applied in X → Y → Z order

ax = deg2rad(axDeg);
ay = deg2rad(ayDeg);
az = deg2rad(azDeg);

Rx = [1 0 0; 0 cos(ax) -sin(ax); 0 sin(ax) cos(ax)];
Ry = [cos(ay) 0 sin(ay); 0 1 0; -sin(ay) 0 cos(ay)];
Rz = [cos(az) -sin(az) 0; sin(az) cos(az) 0; 0 0 1];

R = Rx * Ry * Rz;
end

function v = wrapTo180(v)
% Wrap angle in degrees to [-180,180]
v = mod(v + 180, 360) - 180;
end