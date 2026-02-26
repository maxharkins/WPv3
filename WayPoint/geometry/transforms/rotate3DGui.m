function [coordsOut, didApply, Rfinal] = rotate3DGui(coordsIn, varargin)
% rotate3DGui
% Discrete interactive orientation helper for Nx3 coordinates.
% Rotations are quantized to +/-90 degrees about global X/Y/Z axes.
%
% Usage:
%   [coordsRot, didApply, R] = rotate3DGui(coords, 'Title', 'Rotate STL');
%
% Inputs:
%   coordsIn : Nx3 double
%
% Name-Value:
%   'Title'         : window title (default "Rotate 3D Geometry")
%   'PointSize'     : scatter point size (default 8)
%   'UseScatter'    : true=render as scatter3, false=render as patch if faces provided
%   'Faces'         : Mx3 triangulation (optional)
%   'ShowAxesTriad' : true/false (default true)
%
% Outputs:
%   coordsOut : rotated coordinates (same size as input)
%   didApply  : logical, true if user hit Apply, false if Cancel/closed
%   Rfinal    : 3x3 rotation matrix applied (about origin)

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

gl = uigridlayout(fig, [1 2]);
gl.ColumnWidth = {'1x', 320};
gl.RowHeight   = {'1x'};

ax = uiaxes(gl);
ax.Box = 'on';
ax.DataAspectRatio = [1 1 1];
grid(ax, 'on');
xlabel(ax,'X'); ylabel(ax,'Y'); zlabel(ax,'Z');
title(ax,'Rotate with +/-90 buttons. Apply to accept.');
set(ax, 'Projection', 'perspective');
ax.ZDir = 'reverse';
ax.View = [-41.3249 21.6465];

panel = uipanel(gl, 'Title', 'Rotation Controls');
pg = uigridlayout(panel, [14 3]);
pg.RowHeight = {22,30,30,30,22,30,30,30,22,30,30,'1x',32,32};
pg.ColumnWidth = {90,'1x',90};

% Internal state: exact orientation matrix (orthonormal, entries in {-1,0,1})
state.R = eye(3);

hGeom = [];
hTriad = [];

renderGeometry();
updateTriad();
updateRotationText();

lblX = uilabel(pg, 'Text', 'Rotate X', 'HorizontalAlignment', 'left');
lblX.Layout.Row = 1;
lblX.Layout.Column = 1;
btnXn = uibutton(pg, 'Text', 'X -90', 'ButtonPushedFcn', @(~,~) rotateStep('x', -1));
btnXn.Layout.Row = 2; btnXn.Layout.Column = 1;
btnXp = uibutton(pg, 'Text', 'X +90', 'ButtonPushedFcn', @(~,~) rotateStep('x', +1));
btnXp.Layout.Row = 2; btnXp.Layout.Column = 3;

lblY = uilabel(pg, 'Text', 'Rotate Y', 'HorizontalAlignment', 'left');
lblY.Layout.Row = 5;
lblY.Layout.Column = 1;
btnYn = uibutton(pg, 'Text', 'Y -90', 'ButtonPushedFcn', @(~,~) rotateStep('y', -1));
btnYn.Layout.Row = 6; btnYn.Layout.Column = 1;
btnYp = uibutton(pg, 'Text', 'Y +90', 'ButtonPushedFcn', @(~,~) rotateStep('y', +1));
btnYp.Layout.Row = 6; btnYp.Layout.Column = 3;

lblZ = uilabel(pg, 'Text', 'Rotate Z', 'HorizontalAlignment', 'left');
lblZ.Layout.Row = 9;
lblZ.Layout.Column = 1;
btnZn = uibutton(pg, 'Text', 'Z -90', 'ButtonPushedFcn', @(~,~) rotateStep('z', -1));
btnZn.Layout.Row = 10; btnZn.Layout.Column = 1;
btnZp = uibutton(pg, 'Text', 'Z +90', 'ButtonPushedFcn', @(~,~) rotateStep('z', +1));
btnZp.Layout.Row = 10; btnZp.Layout.Column = 3;

rotText = uitextarea(pg, ...
    'Value', {'R = eye(3)'}, ...
    'Editable', 'off');
rotText.Layout.Row = 12;
rotText.Layout.Column = [1 3];

btnReset = uibutton(pg, ...
    'Text', 'Reset Rot', ...
    'ButtonPushedFcn', @(~,~) resetRot());
btnReset.Layout.Row = 11;
btnReset.Layout.Column = 1;

btnTop = uibutton(pg, 'Text', 'XY (Top)', 'ButtonPushedFcn', @(~,~) view(ax, 0, 90));
btnTop.Layout.Row = 3; btnTop.Layout.Column = 2;
btnFront = uibutton(pg, 'Text', 'XZ (Front)', 'ButtonPushedFcn', @(~,~) view(ax, 0, 0));
btnFront.Layout.Row = 4; btnFront.Layout.Column = 2;
btnSide = uibutton(pg, 'Text', 'YZ (Side)', 'ButtonPushedFcn', @(~,~) view(ax, 90, 0));
btnSide.Layout.Row = 5; btnSide.Layout.Column = 2;

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

uiwait(fig);

% ---------------------------
% Nested callbacks
% ---------------------------
    function rotateStep(axisChar, dirSign)
        Rstep = rotationStepMatrix90(axisChar, dirSign);
        state.R = Rstep * state.R;
        rerender();
    end

    function resetRot()
        state.R = eye(3);
        rerender();
    end

    function rerender()
        camState.Position  = campos(ax);
        camState.Target    = camtarget(ax);
        camState.UpVector  = camup(ax);
        camState.ViewAngle = camva(ax);

        coordsOut = applyRotationMatrix(coordsIn, state.R);
        Rfinal = state.R;

        updateGeometry(coordsOut);
        updateTriad();
        updateRotationText();

        campos(ax, camState.Position);
        camtarget(ax, camState.Target);
        camup(ax, camState.UpVector);
        camva(ax, camState.ViewAngle);

        drawnow limitrate;
    end

    function onApply(~,~)
        didApply = true;
        coordsOut = applyRotationMatrix(coordsIn, state.R);
        Rfinal = state.R;
        uiresume(fig);
        delete(fig);
    end

    function onCancel(~,~)
        didApply = false;
        coordsOut = coordsIn;
        Rfinal = eye(3);
        if isvalid(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function updateRotationText()
        R = round(state.R);
        rotText.Value = {
            'R =', ...
            sprintf('[ %2d %2d %2d ]', R(1,1), R(1,2), R(1,3)), ...
            sprintf('[ %2d %2d %2d ]', R(2,1), R(2,2), R(2,3)), ...
            sprintf('[ %2d %2d %2d ]', R(3,1), R(3,2), R(3,3))
        };
    end

    function renderGeometry()
        cla(ax);

        % CENTER
        minVals = min(coordsOut, [], 1);
        maxVals = max(coordsOut, [], 1);
        bbCenter = (minVals + maxVals) / 2;
        coordsOut = coordsOut - bbCenter;

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
            hGeom = scatter3(ax, ...
                coordsOut(:,1), ...
                coordsOut(:,2), ...
                coordsOut(:,3), ...
                p.Results.PointSize, ...
                'filled');
        end

        axis(ax,'equal');
        rotate3d(ax,'on');

        r = max(vecnorm(coordsOut,2,2));
        R = 1.05 * r;
        xlim(ax, [-R R]);
        ylim(ax, [-R R]);
        zlim(ax, [-R R]);
        axis(ax,'manual');
    end

    function updateGeometry(c)
        % CENTER
        minVals = min(c, [], 1);
        maxVals = max(c, [], 1);
        bbCenter = (minVals + maxVals) / 2;
        c = c - bbCenter;

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
            hGeom.Vertices = c;
        end
    end

    function updateTriad()
        if ~p.Results.ShowAxesTriad
            if ~isempty(hTriad) && all(isvalid(hTriad)), delete(hTriad); end
            hTriad = [];
            return;
        end

        if ~isempty(hTriad)
            try
                delete(hTriad(isvalid(hTriad)));
            catch
            end
        end

        spans = max(coordsOut,[],1) - min(coordsOut,[],1);
        L = 0.15 * max(spans);
        if ~(isfinite(L) && L > 0)
            L = 1;
        end

        R = state.R;
        ex = (R*[L;0;0])';
        ey = (R*[0;L;0])';
        ez = (R*[0;0;L])';

        hold(ax,'on');
        hTriad(1) = plot3(ax, [0 ex(1)], [0 ex(2)], [0 ex(3)], 'r-', 'LineWidth', 2);
        hTriad(2) = plot3(ax, [0 ey(1)], [0 ey(2)], [0 ey(3)], 'g-', 'LineWidth', 2);
        hTriad(3) = plot3(ax, [0 ez(1)], [0 ez(2)], [0 ez(3)], 'b-', 'LineWidth', 2);
        hold(ax,'off');
    end

end

% ---------------------------
% Local helpers
% ---------------------------
function cRot = applyRotationMatrix(c, R)
cRot = (R * c')';
end

function Rstep = rotationStepMatrix90(axisChar, dirSign)
% dirSign: +1 => +90 deg, -1 => -90 deg (right-hand rule, global axis)
% NOTE: I switched case x and y and now it follows RHR. DO NOT CHANGE. 
% I am not sure what the issue was before.
switch lower(axisChar)
    case 'y'  % DO NOT CHANGE
        if dirSign > 0
            Rstep = [1 0 0; 0 0 -1; 0 1 0];
        else
            Rstep = [1 0 0; 0 0 1; 0 -1 0];
        end
    case 'x' % DO NOT CHANGE
        if dirSign > 0
            Rstep = [0 0 1; 0 1 0; -1 0 0];
        else
            Rstep = [0 0 -1; 0 1 0; 1 0 0];
        end
    case 'z'
        if dirSign > 0
            Rstep = [0 -1 0; 1 0 0; 0 0 1];
        else
            Rstep = [0 1 0; -1 0 0; 0 0 1];
        end
    otherwise
        error('Unknown axis "%s". Use x, y, or z.', axisChar);
end
end
