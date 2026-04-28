% Multi-site cylindrical channel ablation in one FOV (no XY stage moves).
%
% Geometry per site:
%   - X-Z cross section: circular with diameter = diameter_xz_um
%   - Extrusion axis    : Y with length = length_y_um
%
% Workflow:
% 1) Edit USER CONFIG.
% 2) Run this script.
% 3) Script calls captureGrab() before and after ablation and waits for completion.
%
% scan_list columns:
%   [center_x_um, center_y_um, center_z_um, pixel_dwell_s, power]
%
% power is interpreted using power_units:
%   - 'fraction' : [0..1]
%   - 'percent'  : [0..100]

%% ========================= USER CONFIG =========================

% Same channel geometry for every site.
diameter_xz_um = 50;   % circular diameter in X-Z
length_y_um    = 880;   % extrusion length along Y

% Sampling/grid settings.
spacing_x_um = 0.40;   % spacing between raster lines in X (within a Z layer)
spacing_y_um = 0.40;   % point spacing along Y in each raster line
spacing_z_um = 2;   % Z spacing (PSF ~1.5 um top-to-bottom -> 0.75 um step)

% Z sampling mode for the circular X-Z profile:
%   'grid_only'    -> sample only at z = k*spacing_z_um relative to z_center
%                     (strict discrete Z regions; may not hit exact circle edges)
%   'include_edges' -> also include +/-radius and 0 even if off-grid
z_sampling_mode = 'grid_only';

% [x_um, y_um, z_um, pixel_dwell_s, power]
scan_list = [
   0,   0, 150, 0.08e-3, 1.00;
];

power_units = 'fraction';   % 'fraction' or 'percent'

% Site order:
%   false -> run in the order you list in scan_list
%   true  -> keep first site fixed, then nearest-neighbor XY ordering
reorder_sites_for_speed = false;

% Motion/playback behavior
z_settle_s           = 0.00;
z_move_tol_um        = 1e-6;
lead_in_s            = 0.00;
tail_out_s           = 0.00;
turn_blanking        = true;
turn_angle_deg       = 55;
turn_blank_s         = 0;
allow_unsynced_beam  = true;
capture_timeout_s    = inf;  % set finite timeout if captureGrab can hang
motor_overhead_per_slice_s = 0.70; % estimate-only additive overhead per Z layer

% Optional beam waist override for playback spacing model.
% Set NaN to use hWP.Settings.BeamWaistDiameter_um.
beam_waist_um_override = NaN;
overlap_fraction = 0.75; % [0,1): 0.75 => spacing is 25% of beam waist diameter

verbose = true;

% Visualization (layer-by-layer beam path preview during execution)
plot_layer_paths = false;
plot_decimation = 5;   % keep every Nth point for plotting
plot_pause_s = 0.00;   % optional pause after each plot update

%% ======================= END USER CONFIG =======================

assert(isnumeric(scan_list) && size(scan_list,2) == 5, ...
    'scan_list must be Nx5: [x_um, y_um, z_um, pixel_dwell_s, power].');
assert(~isempty(scan_list), 'scan_list is empty.');
assert(all(isfinite(scan_list(:,1:4)), 'all'), ...
    'x, y, z, and pixel dwell entries must be finite.');
assert(all(scan_list(:,4) > 0), 'Pixel dwell times must be > 0.');
validateattributes(diameter_xz_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(length_y_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(spacing_x_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(spacing_y_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(spacing_z_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(overlap_fraction, {'numeric'}, {'scalar', 'finite', '>=', 0, '<', 1});
validateattributes(plot_decimation, {'numeric'}, {'scalar', 'finite', 'integer', '>=', 1});
validateattributes(plot_pause_s, {'numeric'}, {'scalar', 'finite', '>=', 0});
validateattributes(motor_overhead_per_slice_s, {'numeric'}, {'scalar', 'finite', '>=', 0});
assert(any(strcmpi(z_sampling_mode, {'grid_only','include_edges'})), ...
    'z_sampling_mode must be ''grid_only'' or ''include_edges''.');

[hWP, hSI] = resolveHandles();
[beam, hX, hY] = resolveScanHardware(hWP);
beam_waist_um = resolveBeamWaist(hWP, beam_waist_um_override);

[z_rel_um, x_templates, y_templates] = buildCylinderLayerTemplates( ...
    diameter_xz_um, length_y_um, spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode);

radius_um = diameter_xz_um / 2;
half_y = length_y_um / 2;
assert(all(abs(scan_list(:,1)) + radius_um <= 500), ...
    'At least one site exceeds the +/-500 um X galvo range.');
assert(all(abs(scan_list(:,2)) + half_y <= 500), ...
    'At least one site exceeds the +/-500 um Y galvo range.');

site_order = buildSiteOrder(scan_list(:,1:2), reorder_sites_for_speed);
scan_run = scan_list(site_order, :);
timing_est = estimateRunTiming(scan_run, z_rel_um, x_templates, y_templates, ...
    lead_in_s, tail_out_s, turn_blanking, turn_angle_deg, turn_blank_s, ...
    z_settle_s, z_move_tol_um, motor_overhead_per_slice_s);
plot_state = initLayerPlot(plot_layer_paths, scan_run, z_rel_um, length_y_um);


if verbose
    notifyMe(sprintf("Scan Estimated Completion: %s", timing_est.eta_adjusted))

    fprintf('\nPlanned sites: %d\n', size(scan_run,1));
    fprintf('Geometry: diameter(XZ)=%.3f um, length(Y)=%.3f um\n', ...
        diameter_xz_um, length_y_um);
    fprintf('Spacing: dX=%.3f um, dY=%.3f um, dZ=%.3f um | z mode: %s\n', ...
        spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode);
    fprintf('Playback overlap fraction: %.3f (from beam waist)\n', overlap_fraction);
    fprintf('Layers per site: %d (deep->shallow, high z -> low z)\n\n', numel(z_rel_um));
    fprintf('Estimated duration (nominal): %s (%.1f s) | ETA %s\n', ...
        formatDurationHMS(timing_est.nominal_s), timing_est.nominal_s, char(timing_est.eta_nominal));
    fprintf('Estimated duration (+%.2f s/layer): %s (%.1f s) | ETA %s\n\n', ...
        motor_overhead_per_slice_s, formatDurationHMS(timing_est.adjusted_s), ...
        timing_est.adjusted_s, char(timing_est.eta_adjusted));
end

results = repmat(struct( ...
    'run_index', NaN, ...
    'source_index', NaN, ...
    'center_xy_um', [NaN NaN], ...
    'z_center_um', NaN, ...
    'pixel_dwell_s', NaN, ...
    'power_fraction', NaN, ...
    'num_layers', NaN, ...
    'layer_z_um', [], ...
    'layer_elapsed_s', [], ...
    'elapsed_s', NaN, ...
    'layer_stats', {{}}), size(scan_run,1), 1);

last_z = NaN;
model = [];

try
    if verbose, fprintf('captureGrab() before scan sequence...\n'); end
    runCaptureGrabBlocking(capture_timeout_s);

    t_run = tic;
    for i = 1:size(scan_run,1)
        cx = scan_run(i,1);
        cy = scan_run(i,2);
        z_center_um = scan_run(i,3);
        pdt_s = scan_run(i,4);
        pf = normalizePower(scan_run(i,5), power_units);

        layer_z_um = z_center_um + z_rel_um;
        layer_elapsed_s = nan(numel(z_rel_um),1);
        layer_stats = cell(numel(z_rel_um),1);

        t_site = tic;
        for li = 1:numel(z_rel_um)
            z_target_um = layer_z_um(li);

            if isnan(last_z) || abs(z_target_um - last_z) > z_move_tol_um
                hSI.hMotors.moveSampleNoQuery([NaN, NaN, z_target_um], true);
                if z_settle_s > 0
                    pause(z_settle_s);
                end
                last_z = z_target_um;
            end

            x_play = x_templates{li} + cx;
            y_play = y_templates{li} + cy;

            updateLayerPlot(plot_state, ...
                x_play, y_play, z_target_um, ...
                i, size(scan_run,1), site_order(i), li, numel(z_rel_um), ...
                plot_decimation, plot_pause_s);

            t_layer = tic;
            [stats, model] = playPreexistingPathSIStyle( ...
                hX, hY, x_play, y_play, pdt_s, ...
                'BeamWaistDiameter_um', beam_waist_um, ...
                'OverlapFraction', overlap_fraction, ...
                'Model', model, ...
                'LeadIn_s', lead_in_s, ...
                'TailOut_s', tail_out_s, ...
                'BeamHandle', beam, ...
                'PowerFrac', pf, ...
                'BlankSharpTurns', turn_blanking, ...
                'TurnAngle_deg', turn_angle_deg, ...
                'TurnBlank_s', turn_blank_s, ...
                'AllowUnsyncedBeam', allow_unsynced_beam, ...
                'ParkWhenDone', false);
            elapsed_layer = toc(t_layer);

            layer_elapsed_s(li) = elapsed_layer;
            layer_stats{li} = stats;

            if verbose
                fprintf(['site %d/%d | src #%d | layer %d/%d | ' ...
                         '[%.3f %.3f %.3f] um | PDT %.3g s | Pf %.3f | %.3f s\n'], ...
                        i, size(scan_run,1), site_order(i), li, numel(z_rel_um), ...
                        cx, cy, z_target_um, pdt_s, pf, elapsed_layer);
            end
        end
        elapsed_site = toc(t_site);

        results(i).run_index = i;
        results(i).source_index = site_order(i);
        results(i).center_xy_um = [cx, cy];
        results(i).z_center_um = z_center_um;
        results(i).pixel_dwell_s = pdt_s;
        results(i).power_fraction = pf;
        results(i).num_layers = numel(z_rel_um);
        results(i).layer_z_um = layer_z_um;
        results(i).layer_elapsed_s = layer_elapsed_s;
        results(i).elapsed_s = elapsed_site;
        results(i).layer_stats = layer_stats;
    end
    run_elapsed_s = toc(t_run);

    try
        beam.setPowerFraction(0);
    catch
    end

    if verbose
        fprintf('\nScan sequence finished in %.3f s.\n', run_elapsed_s);
        fprintf('captureGrab() after scan sequence...\n');
    end
    runCaptureGrabBlocking(capture_timeout_s);

catch ME
    try
        beam.setPowerFraction(0);
    catch
    end
    try
        warning('Error occurred. Running final captureGrab() before rethrow.');
        runCaptureGrabBlocking(capture_timeout_s);
    catch ME2
        warn_id = char(ME2.identifier);
        warn_msg = char(ME2.message);
        if ~isempty(warn_id)
            warning(warn_id, '%s', warn_msg);
        else
            warning('burn_multi_circular_scans_one_fov:CaptureGrabFinalFailed', ...
                '%s', warn_msg);
        end
    end
    rethrow(ME);
end

assignin('base', 'multi_circular_scan_results', results);
if verbose
    notifyMe("Scan Completed!")
    fprintf('Saved results to base workspace variable: multi_circular_scan_results\n');
end

function [hWP, hSI] = resolveHandles()
    if evalin('base', 'exist(''hWP'',''var'')')
        hWP = evalin('base', 'hWP');
    else
        error('hWP was not found in the base workspace.');
    end
    assert(isobject(hWP) && isvalid(hWP), 'hWP handle is invalid.');
    hSI = hWP.hSI;
    assert(isobject(hSI) && isvalid(hSI), 'hSI handle is invalid.');
end

function [beam, hX, hY] = resolveScanHardware(hWP)
    beam = hWP.hSI.hScan2D.hBeams{1};
    [hX, hY] = getXYGalvos(hWP);
    assert(~isempty(hX) && ~isempty(hY), 'Could not resolve X/Y galvo handles.');
end

function beam_waist_um = resolveBeamWaist(hWP, beam_waist_um_override)
    if isfinite(beam_waist_um_override) && beam_waist_um_override > 0
        beam_waist_um = beam_waist_um_override;
        return;
    end
    beam_waist_um = 0.80;
    if isprop(hWP, 'Settings') && isstruct(hWP.Settings) && ...
            isfield(hWP.Settings, 'BeamWaistDiameter_um') && ...
            isfinite(hWP.Settings.BeamWaistDiameter_um) && ...
            hWP.Settings.BeamWaistDiameter_um > 0
        beam_waist_um = double(hWP.Settings.BeamWaistDiameter_um);
    end
end

function pf = normalizePower(power_value, power_units)
    switch lower(string(power_units))
        case "fraction"
            pf = double(power_value);
        case "percent"
            pf = double(power_value) / 100;
        otherwise
            error('power_units must be ''fraction'' or ''percent''.');
    end
    if ~(isfinite(pf) && pf >= 0 && pf <= 1)
        error('Power value %g (%s) maps to invalid fraction %g. Expected [0..1].', ...
            power_value, power_units, pf);
    end
end

function order = buildSiteOrder(xy, do_reorder)
    n = size(xy,1);
    order = (1:n).';
    if ~do_reorder || n <= 2
        return;
    end

    used = false(n,1);
    order(1) = 1;
    used(1) = true;

    for i = 2:n
        prev = xy(order(i-1), :);
        d = hypot(xy(:,1) - prev(1), xy(:,2) - prev(2));
        d(used) = inf;
        [~, next_idx] = min(d);
        order(i) = next_idx;
        used(next_idx) = true;
    end
end

function [z_rel_um, x_templates, y_templates] = buildCylinderLayerTemplates( ...
    diameter_xz_um, length_y_um, spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode)

    radius_um = diameter_xz_um / 2;
    z_rel_um = buildCircularZOffsets(radius_um, spacing_z_um, z_sampling_mode);

    nL = numel(z_rel_um);
    x_templates = cell(nL,1);
    y_templates = cell(nL,1);

    for li = 1:nL
        dz = z_rel_um(li);
        x_half = sqrt(max(radius_um^2 - dz^2, 0));
        [x_templates{li}, y_templates{li}] = generateExtrudedLayerSnake( ...
            x_half, length_y_um, spacing_x_um, spacing_y_um);
    end
end

function z_rel_um = buildCircularZOffsets(radius_um, spacing_z_um, z_sampling_mode)
    if radius_um <= 0
        z_rel_um = 0;
        return;
    end

    switch lower(string(z_sampling_mode))
        case "grid_only"
            % Strictly sample only at discrete z regions k*spacing_z_um around z_center.
            k_max = floor((radius_um + 1e-12) / spacing_z_um);
            if k_max < 1
                z_rel_um = 0;
            else
                z_rel_um = (-k_max:k_max).' * spacing_z_um;
            end

        case "include_edges"
            z_rel_um = (-radius_um:spacing_z_um:radius_um).';
            z_rel_um = unique([z_rel_um; -radius_um; 0; radius_um]);

        otherwise
            error('Unsupported z_sampling_mode: %s', string(z_sampling_mode));
    end

    % Deep to shallow: higher z first.
    z_rel_um = sort(z_rel_um, 'descend');
end

function [x_um, y_um] = generateExtrudedLayerSnake(x_half_um, length_y_um, dx_um, dy_um)
    validateattributes(x_half_um, {'numeric'}, {'scalar', 'finite', 'nonnegative'});
    validateattributes(length_y_um, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(dx_um, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(dy_um, {'numeric'}, {'scalar', 'finite', 'positive'});

    if x_half_um <= 0
        x_line = 0;
    else
        x_line = (-x_half_um:dx_um:x_half_um);
        if isempty(x_line) || abs(x_line(end) - x_half_um) > 1e-12
            x_line = [x_line, x_half_um];
        end
        if abs(x_line(1) + x_half_um) > 1e-12
            x_line = [-x_half_um, x_line];
        end
    end

    y_min = -length_y_um / 2;
    y_max =  length_y_um / 2;
    y_lines = y_min:dy_um:y_max;
    if isempty(y_lines) || abs(y_lines(end) - y_max) > 1e-12
        y_lines = [y_lines, y_max];
    end
    if abs(y_lines(1) - y_min) > 1e-12
        y_lines = [y_min, y_lines];
    end
    if numel(y_lines) < 2
        y_lines = [y_min, y_max];
    end

    x_um = zeros(0,1);
    y_um = zeros(0,1);

    % Desired snake:
    % go across X, step in Y, go across X, step in Y, ...
    for i = 1:numel(y_lines)
        x_local = x_line;
        if mod(i,2) == 0
            x_local = fliplr(x_local);
        end
        y_local = y_lines(i) * ones(size(x_local));

        x_um = [x_um; x_local(:)]; %#ok<AGROW>
        y_um = [y_um; y_local(:)]; %#ok<AGROW>
    end

    keep = [true; hypot(diff(x_um), diff(y_um)) > 0];
    x_um = x_um(keep);
    y_um = y_um(keep);
end

function plot_state = initLayerPlot(enable_plot, scan_run, z_rel_um, length_y_um)
    plot_state = struct('enabled', false);
    if ~enable_plot
        return;
    end

    try
        fig = figure('Name', 'Beam Path Layer-by-Layer', 'NumberTitle', 'off');
        t = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        axXY = nexttile(t, 1);
        axXZ = nexttile(t, 2);

        hXY = plot(axXY, nan, nan, 'b-', 'LineWidth', 1.0);
        hXYStart = plot(axXY, nan, nan, 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 5);
        hXYEnd = plot(axXY, nan, nan, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        hold(axXY, 'off');
        axis(axXY, 'equal');
        xlim(axXY, [-500 500]);
        y_half = length_y_um / 2;
        y_lim = [min(scan_run(:,2) - y_half), max(scan_run(:,2) + y_half)];
        y_margin = max(5, 0.05 * max(1, diff(y_lim)));
        ylim(axXY, y_lim + [-y_margin, y_margin]);
        grid(axXY, 'on');
        xlabel(axXY, 'X (\mum)');
        ylabel(axXY, 'Y (\mum)');
        title(axXY, 'Current XY Beam Path');

        n_sites = size(scan_run,1);
        n_layers = numel(z_rel_um);
        all_x = repelem(scan_run(:,1), n_layers, 1);
        all_z = zeros(n_sites * n_layers, 1);
        w = 1;
        for s = 1:n_sites
            zz = scan_run(s,3) + z_rel_um;
            all_z(w:w+n_layers-1) = zz(:);
            w = w + n_layers;
        end

        scatter(axXZ, all_x, all_z, 8, [0.75 0.75 0.75], 'filled');
        hold(axXZ, 'on');
        hXZCurrent = plot(axXZ, nan, nan, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        hXZSpan = plot(axXZ, nan, nan, 'r-', 'LineWidth', 1.5);
        hold(axXZ, 'off');
        x_margin = max(5, 0.05 * max(1, range(all_x)));
        z_margin = max(2, 0.05 * max(1, range(all_z)));
        xlim(axXZ, [min(all_x)-x_margin, max(all_x)+x_margin]);
        ylim(axXZ, [min(all_z)-z_margin, max(all_z)+z_margin]);
        grid(axXZ, 'on');
        xlabel(axXZ, 'X (\mum)');
        ylabel(axXZ, 'Z (\mum)');
        title(axXZ, 'Planned/Current X-Z Layers');

        drawnow;

        plot_state.enabled = true;
        plot_state.fig = fig;
        plot_state.axXY = axXY;
        plot_state.axXZ = axXZ;
        plot_state.hXY = hXY;
        plot_state.hXYStart = hXYStart;
        plot_state.hXYEnd = hXYEnd;
        plot_state.hXZCurrent = hXZCurrent;
        plot_state.hXZSpan = hXZSpan;
    catch ME
        warning('burn_multi_circular_scans_one_fov:PlotInitFailed', ...
            'Layer plotting disabled: %s', ME.message);
        plot_state = struct('enabled', false);
    end
end

function updateLayerPlot(plot_state, x_play, y_play, z_target_um, ...
    site_idx, n_sites, source_idx, layer_idx, n_layers, decim, pause_s)

    if ~isfield(plot_state, 'enabled') || ~plot_state.enabled
        return;
    end
    if ~isgraphics(plot_state.fig)
        return;
    end

    decim = max(1, round(decim));
    idx = 1:decim:numel(x_play);
    if idx(end) ~= numel(x_play)
        idx = [idx, numel(x_play)];
    end
    x_plot = x_play(idx);
    y_plot = y_play(idx);

    set(plot_state.hXY, 'XData', x_plot, 'YData', y_plot);
    set(plot_state.hXYStart, 'XData', x_play(1), 'YData', y_play(1));
    set(plot_state.hXYEnd, 'XData', x_play(end), 'YData', y_play(end));
    title(plot_state.axXY, sprintf(['Current XY Beam Path | site %d/%d (src %d) ' ...
        '| layer %d/%d | Z=%.3f \\mum'], ...
        site_idx, n_sites, source_idx, layer_idx, n_layers, z_target_um));

    set(plot_state.hXZCurrent, 'XData', mean(x_play), 'YData', z_target_um);
    set(plot_state.hXZSpan, 'XData', [min(x_play), max(x_play)], ...
        'YData', [z_target_um, z_target_um]);

    drawnow limitrate;
    if pause_s > 0
        pause(pause_s);
    end
end

function runCaptureGrabBlocking(timeout_s)
    return
    if exist('captureGrab', 'file') ~= 2 && exist('captureGrab', 'builtin') ~= 5
        error('captureGrab() is required but was not found.');
    end

    token = captureGrab();
    waitOnCaptureToken(token, timeout_s);
end

function waitOnCaptureToken(token, timeout_s)
    if nargin < 2 || isempty(timeout_s)
        timeout_s = inf;
    end

    if isempty(token)
        return;
    end

    if isa(token, 'parallel.FevalFuture') || isa(token, 'parallel.Future')
        if isfinite(timeout_s)
            wait(token, timeout_s);
            assert(strcmp(string(token.State), "finished"), ...
                'captureGrab() future did not finish before timeout.');
        else
            wait(token);
        end
        return;
    end

    if isobject(token)
        if ismethod(token, 'wait')
            if isfinite(timeout_s)
                t0 = tic;
                while toc(t0) < timeout_s
                    try
                        token.wait();
                        return;
                    catch
                        pause(0.05);
                    end
                end
                error('captureGrab() did not finish before timeout.');
            else
                token.wait();
                return;
            end
        end

        if isprop(token, 'Done') || isprop(token, 'IsDone')
            t0 = tic;
            while true
                done = false;
                try
                    if isprop(token, 'Done'), done = logical(token.Done); end
                    if isprop(token, 'IsDone'), done = logical(token.IsDone); end
                catch
                end
                if done
                    return;
                end
                if isfinite(timeout_s) && toc(t0) > timeout_s
                    error('captureGrab() did not finish before timeout.');
                end
                pause(0.05);
            end
        end
    end
    % If token type is unknown, assume captureGrab() was already blocking.
end

function timing_est = estimateRunTiming(scan_run, z_rel_um, x_templates, y_templates, ...
    lead_in_s, tail_out_s, turn_blanking, turn_angle_deg, turn_blank_s, ...
    z_settle_s, z_move_tol_um, motor_overhead_per_slice_s)

    n_sites = size(scan_run, 1);
    n_layers = numel(z_rel_um);
    total_layers = n_sites * n_layers;

    points_per_layer = zeros(n_layers, 1);
    sharp_turns_per_layer = zeros(n_layers, 1);
    for li = 1:n_layers
        points_per_layer(li) = numel(x_templates{li});
        if turn_blanking && turn_blank_s > 0
            sharp_turns_per_layer(li) = countSharpTurns( ...
                x_templates{li}, y_templates{li}, turn_angle_deg);
        end
    end

    points_per_site = sum(points_per_layer);
    dwell_s = points_per_site * sum(scan_run(:,4));
    lead_tail_s = total_layers * (lead_in_s + tail_out_s);
    turn_blank_total_s = n_sites * sum(sharp_turns_per_layer) * turn_blank_s;
    z_move_count = countPlannedZMoves(scan_run(:,3), z_rel_um, z_move_tol_um);
    z_settle_total_s = z_move_count * z_settle_s;

    nominal_s = dwell_s + lead_tail_s + turn_blank_total_s + z_settle_total_s;
    motor_adjust_s = total_layers * motor_overhead_per_slice_s;
    adjusted_s = nominal_s + motor_adjust_s;

    eta_nominal = datetime('now') + seconds(nominal_s);
    eta_adjusted = datetime('now') + seconds(adjusted_s);
    eta_nominal.Format = 'yyyy-MM-dd HH:mm:ss';
    eta_adjusted.Format = 'yyyy-MM-dd HH:mm:ss';

    timing_est = struct( ...
        'total_layers', total_layers, ...
        'dwell_s', dwell_s, ...
        'lead_tail_s', lead_tail_s, ...
        'turn_blank_s', turn_blank_total_s, ...
        'z_settle_s', z_settle_total_s, ...
        'nominal_s', nominal_s, ...
        'motor_adjust_s', motor_adjust_s, ...
        'adjusted_s', adjusted_s, ...
        'eta_nominal', eta_nominal, ...
        'eta_adjusted', eta_adjusted);
end

function n_moves = countPlannedZMoves(z_centers_um, z_rel_um, z_move_tol_um)
    n_moves = 0;
    last_z = NaN;
    for si = 1:numel(z_centers_um)
        z_layers = z_centers_um(si) + z_rel_um;
        for li = 1:numel(z_layers)
            z_target = z_layers(li);
            if isnan(last_z) || abs(z_target - last_z) > z_move_tol_um
                n_moves = n_moves + 1;
                last_z = z_target;
            end
        end
    end
end

function n_sharp = countSharpTurns(x_um, y_um, turn_angle_deg)
    n_sharp = 0;
    if numel(x_um) < 3
        return;
    end

    p = [x_um(:), y_um(:)];
    v1 = p(2:end-1,:) - p(1:end-2,:);
    v2 = p(3:end,:) - p(2:end-1,:);
    n1 = hypot(v1(:,1), v1(:,2));
    n2 = hypot(v2(:,1), v2(:,2));
    valid = n1 > 0 & n2 > 0;
    if ~any(valid)
        return;
    end

    cos_theta = sum(v1(valid,:) .* v2(valid,:), 2) ./ (n1(valid) .* n2(valid));
    cos_theta = min(1, max(-1, cos_theta));
    turn_angles = acosd(cos_theta);
    n_sharp = sum(turn_angles >= turn_angle_deg);
end

function txt = formatDurationHMS(duration_s)
    txt = char(duration(0, 0, max(0, duration_s), 'Format', 'hh:mm:ss'));
end

function [hX, hY] = getXYGalvos(hWP)
% Try name-based lookup, then fallback to legacy indices 118/119.
    hX = [];
    hY = [];

    try
        rs = hWP.hSI.hResourceStore.hResources;
        for k = 1:numel(rs)
            r = rs{k};
            if isempty(r) || ~isobject(r)
                continue;
            end
            nm = '';
            try
                nm = string(r.name);
            catch
            end
            if contains(lower(nm), "x galvo")
                hX = r;
            elseif contains(lower(nm), "y galvo")
                hY = r;
            end
        end
    catch
    end

    if isempty(hX) || isempty(hY)
        try
            rs = hWP.hSI.hResourceStore.hResources;
            if isempty(hX) && numel(rs) >= 118, hX = rs{118}; end
            if isempty(hY) && numel(rs) >= 119, hY = rs{119}; end
        catch
        end
    end
end
