function [x_theta, y_theta, model] = micronsToDegrees(x_um, y_um, model)
%micronsToDegrees Map (x_um, y_um) [µm] -> (x_theta, y_theta) [deg]
% using a global geometric calibration independent of zoom.
%
% The mapping is an odd rational function:
%   theta(x) [rad] = (a1*x + a3*x.^3) ./ (1 + c2*x.^2)
% fitted to the half-FOV endpoints (x_edge, theta_edge) gathered over zoom.
%
% USAGE
%   [xt, yt] = micronsToDegrees(x_um, y_um);           % auto-calibrate
%   [xt, yt] = micronsToDegrees(x_um, y_um, model);    % reuse model
%   [~, ~, model] = micronsToDegrees([], [], []);      % just get model
%
% NOTES
%   - x_um, y_um can be scalars or arrays; output matches their size.
%   - Coordinates are assumed centered at the scan origin (0 at field center).
%   - The fit is most reliable within |x| <= model.domain_um(2).
%
% AUTHOR ASSUMPTIONS
%   - FOVmicrons(z) is given by your zoom2microns(z).
%   - FOVdegrees(z) uses the same constants you used in getMicronsPerDegree.

    if nargin < 3 || isempty(model)
        model = calibrate_um_to_deg(); % build once; reuse thereafter for speed
    end

    % Vectorized mapping from µm -> degrees via the fitted theta(x)
    thx = theta_from_um(x_um, model);   % [rad]
    thy = theta_from_um(y_um, model);   % [rad]

    x_theta = rad2deg_local(thx);
    y_theta = rad2deg_local(thy);
end

% ---------- helpers ----------

function model = calibrate_um_to_deg(zoomGrid)
% Build the (x_edge, theta_edge) dataset across zoom and fit the model.
% You can edit zoomGrid to reflect your scanner's practical range.

    if nargin < 1 || isempty(zoomGrid)
        zoomGrid = 1.3:0.1:99.9;    % sensible default; adjust if your range differs
    end

    % Gather half-FOV endpoints across zooms (symmetry ⇒ use +x only)
    x_edge_um   = arrayfun(@(z) zoom2microns(z)/2, zoomGrid);       % [µm]
    theta_edge  = arrayfun(@(z) deg2rad_local(localFOVdeg(z)/2), zoomGrid); % [rad]

    % Fit the odd rational model: theta = (a1*x + a3*x^3) / (1 + c2*x^2)
    % Rearranged linear least squares: [x, x^3, -x^2.*theta] * [a1; a3; c2] = theta
    X = [x_edge_um.', (x_edge_um.').^3, -(x_edge_um.').^2 .* theta_edge.'];
    y = theta_edge.';
    coeff = X \ y;  % [a1; a3; c2]

    model.a1 = coeff(1);
    model.a3 = coeff(2);
    model.c2 = coeff(3);
    model.domain_um = [0, max(x_edge_um)];   % recommended validity domain
    model.zoomGridUsed = zoomGrid;

    % Report fit quality at the sampled endpoints (useful sanity check)
    theta_fit = (model.a1*x_edge_um + model.a3*x_edge_um.^3) ./ (1 + model.c2*x_edge_um.^2);
    err_deg   = rad2deg_local(theta_fit - theta_edge);
    model.rms_fit_deg = sqrt(mean(err_deg.^2));
    model.max_abs_err_deg = max(abs(err_deg));
end

function th = theta_from_um(x_um, model)
% Apply the fitted odd rational mapping (returns radians).
    th = (model.a1.*x_um + model.a3.*x_um.^3) ./ (1 + model.c2.*x_um.^2);
end

function d = localFOVdeg(zoomFactor)
% Reproduce your FOVdegrees formula used inside getMicronsPerDegree
% (kept local to avoid changing your existing functions).
    defaultRoiSize = 20.0998;
    fillFractionSpatial = 0.9000;
    d = defaultRoiSize ./ zoomFactor .* fillFractionSpatial; % [deg], total FOV
end

function r = deg2rad_local(d), r = d * (pi/180); end
function d = rad2deg_local(r), d = r * (180/pi); end
