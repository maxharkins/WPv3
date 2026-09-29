% Image-guided rectangular-prism ablation in one FOV (no XY stage moves).
%
% This script mirrors ablate_channel.m playback behavior, but geometry is:
%   - XY footprint: rectangle selected interactively on an image
%   - Z extent    : rectangular prism height selected by user
%
% Workflow:
% 1) Run this script.
% 2) Pick an image file in the file chooser.
% 3) Confirm/edit numeric settings in the prompt.
% 4) Draw rectangle ROI on the image and double-click the rectangle.
%
% Notes:
% - Coordinates are assumed centered at (0,0) um in the shown image FOV.
% - Default FOV comes from current ScanImage zoom via zoom2microns().
% - The selected ROI is played layer-by-layer in Z using snake raster lines.

%% ========================= USER CONFIG =========================

% Sampling/grid settings for the rectangular prism.
spacing_x_um = 0.80;   % spacing between raster lines in X (within each Z layer)
spacing_y_um = 0.80;   % point spacing along Y in each raster line
spacing_z_um = 3.00;   % Z spacing between prism layers

% Z sampling mode:
%   'grid_only'    -> only z = k*spacing_z_um around z_center
%   'include_edges' -> include +/-height/2 even if off-grid
z_sampling_mode = 'grid_only';

% Defaults for the settings prompt.
default_prism_height_um = 50.0;
default_pixel_dwell_s = 0.08e-3;
default_power_fraction = 1.00;

% Motion/playback behavior (same style as ablate_channel.m)
z_settle_s           = 0.00;
z_move_tol_um        = 1e-6;
lead_in_s            = 0.00;
tail_out_s           = 0.00;
turn_blanking        = true;
turn_angle_deg       = 55;
turn_blank_s         = 0;
allow_unsynced_beam  = true;
capture_timeout_s    = inf;  % set finite timeout if captureGrab can hang

% Optional beam waist override for playback spacing model.
% Set NaN to use hWP.Settings.BeamWaistDiameter_um.
beam_waist_um_override = NaN;
overlap_fraction = 0.00; % [0,1): 0.75 => spacing is 25% of beam waist diameter

verbose = true;
plot_layer_paths = true;
plot_decimation = 5;
plot_pause_s = 0.00;

%% ======================= END USER CONFIG =======================

assert(any(strcmpi(z_sampling_mode, {'grid_only', 'include_edges'})), ...
    'z_sampling_mode must be ''grid_only'' or ''include_edges''.');
validateattributes(spacing_x_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(spacing_y_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(spacing_z_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(default_prism_height_um, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(default_pixel_dwell_s, {'numeric'}, {'scalar', 'finite', 'positive'});
validateattributes(default_power_fraction, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 1});
validateattributes(overlap_fraction, {'numeric'}, {'scalar', 'finite', '>=', 0, '<', 1});
validateattributes(plot_decimation, {'numeric'}, {'scalar', 'finite', 'integer', '>=', 1});
validateattributes(plot_pause_s, {'numeric'}, {'scalar', 'finite', '>=', 0});

[hWP, hSI] = resolveHandles();
[beam, hX, hY] = resolveScanHardware(hWP);
beam_waist_um = resolveBeamWaist(hWP, beam_waist_um_override);

img_path = pickImagePath();
img = loadDisplayImage(img_path);
[n_rows, n_cols] = size(img);

default_fov_x_um = estimateDefaultFovXUm(hSI, n_cols);
default_fov_y_um = default_fov_x_um * (n_rows / max(1, n_cols));
default_z_center_um = estimateCurrentZUm(hSI);

settings = promptPrismSettings( ...
    default_fov_x_um, default_fov_y_um, default_prism_height_um, default_z_center_um, ...
    default_pixel_dwell_s, default_power_fraction);

roi = selectRectangleRoiUm(img, settings.fov_x_um, settings.fov_y_um);

[z_rel_um, x_templates, y_templates] = buildRectPrismLayerTemplates( ...
    roi.width_um, roi.length_um, settings.height_um, ...
    spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode);

half_x = roi.width_um / 2;
half_y = roi.length_um / 2;
half_z = settings.height_um / 2;

assert(abs(roi.center_x_um) + half_x <= 500, ...
    'Selected ROI exceeds +/-500 um X galvo range.');
assert(abs(roi.center_y_um) + half_y <= 500, ...
    'Selected ROI exceeds +/-500 um Y galvo range.');

timing_est = estimateRunTiming( ...
    settings.pixel_dwell_s, z_rel_um, x_templates, y_templates, ...
    lead_in_s, tail_out_s, turn_blanking, turn_angle_deg, turn_blank_s, ...
    z_settle_s, z_move_tol_um, settings.z_center_um);

plot_state = initLayerPlotRect( ...
    plot_layer_paths, roi.center_x_um, roi.center_y_um, ...
    roi.width_um, roi.length_um, settings.z_center_um, z_rel_um);

if verbose
    fprintf('\nImage: %s\n', img_path);
    fprintf('ROI center: [%.3f %.3f] um | size XY: %.3f x %.3f um\n', ...
        roi.center_x_um, roi.center_y_um, roi.width_um, roi.length_um);
    fprintf('Prism height Z: %.3f um | Z center: %.3f um\n', ...
        settings.height_um, settings.z_center_um);
    fprintf('Spacing: dX=%.3f um, dY=%.3f um, dZ=%.3f um | z mode: %s\n', ...
        spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode);
    fprintf('Playback overlap fraction: %.3f (from beam waist)\n', overlap_fraction);
    fprintf('Estimated duration: %s (%.1f s)\n\n', ...
        formatDurationHMS(timing_est.nominal_s), timing_est.nominal_s);
end

result = struct( ...
    'image_path', img_path, ...
    'roi', roi, ...
    'z_center_um', settings.z_center_um, ...
    'height_um', settings.height_um, ...
    'pixel_dwell_s', settings.pixel_dwell_s, ...
    'power_fraction', settings.power_fraction, ...
    'num_layers', numel(z_rel_um), ...
    'layer_z_um', settings.z_center_um + z_rel_um, ...
    'layer_elapsed_s', nan(numel(z_rel_um), 1), ...
    'elapsed_s', nan, ...
    'layer_stats', {cell(numel(z_rel_um), 1)}, ...
    'config', struct( ...
        'spacing_x_um', spacing_x_um, ...
        'spacing_y_um', spacing_y_um, ...
        'spacing_z_um', spacing_z_um, ...
        'z_sampling_mode', z_sampling_mode, ...
        'lead_in_s', lead_in_s, ...
        'tail_out_s', tail_out_s, ...
        'turn_blanking', turn_blanking, ...
        'turn_angle_deg', turn_angle_deg, ...
        'turn_blank_s', turn_blank_s, ...
        'allow_unsynced_beam', allow_unsynced_beam, ...
        'beam_waist_um', beam_waist_um, ...
        'overlap_fraction', overlap_fraction));

last_z = NaN;
model = [];

try
    if verbose, fprintf('captureGrab() before scan sequence...\n'); end
    runCaptureGrabBlocking(capture_timeout_s);

    t_run = tic;
    for li = 1:numel(z_rel_um)
        z_target_um = settings.z_center_um + z_rel_um(li);

        if isnan(last_z) || abs(z_target_um - last_z) > z_move_tol_um
            hSI.hMotors.moveSampleNoQuery([NaN, NaN, z_target_um], true);
            if z_settle_s > 0
                pause(z_settle_s);
            end
            last_z = z_target_um;
        end

        x_play = x_templates{li} + roi.center_x_um;
        y_play = y_templates{li} + roi.center_y_um;

        updateLayerPlot(plot_state, ...
            x_play, y_play, z_target_um, li, numel(z_rel_um), ...
            plot_decimation, plot_pause_s);

        t_layer = tic;
        [stats, model] = playPreexistingPathSIStyle( ...
            hX, hY, x_play, y_play, settings.pixel_dwell_s, ...
            'BeamWaistDiameter_um', beam_waist_um, ...
            'OverlapFraction', overlap_fraction, ...
            'Model', model, ...
            'LeadIn_s', lead_in_s, ...
            'TailOut_s', tail_out_s, ...
            'BeamHandle', beam, ...
            'PowerFrac', settings.power_fraction, ...
            'BlankSharpTurns', turn_blanking, ...
            'TurnAngle_deg', turn_angle_deg, ...
            'TurnBlank_s', turn_blank_s, ...
            'AllowUnsyncedBeam', allow_unsynced_beam, ...
            'ParkWhenDone', false);
        elapsed_layer = toc(t_layer);

        result.layer_elapsed_s(li) = elapsed_layer;
        result.layer_stats{li} = stats;

        if verbose
            fprintf(['layer %d/%d | ROI [%.3f %.3f %.3f] um | ' ...
                     'XY %.3f x %.3f um | PDT %.3g s | Pf %.3f | %.3f s\n'], ...
                li, numel(z_rel_um), roi.center_x_um, roi.center_y_um, z_target_um, ...
                roi.width_um, roi.length_um, settings.pixel_dwell_s, ...
                settings.power_fraction, elapsed_layer);
        end
    end
    result.elapsed_s = toc(t_run);

    try
        beam.setPowerFraction(0);
    catch
    end

    if verbose
        fprintf('\nRectangular-prism ablation finished in %.3f s.\n', result.elapsed_s);
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
            warning('ablate_rect_prism_gui:CaptureGrabFinalFailed', '%s', warn_msg);
        end
    end
    rethrow(ME);
end

assignin('base', 'rect_prism_scan_result', result);
if verbose
    fprintf('Saved results to base workspace variable: rect_prism_scan_result\n');
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

function img_path = pickImagePath()
    [fname, fdir] = uigetfile( ...
        {'*.tif;*.tiff;*.png;*.jpg;*.jpeg;*.bmp', 'Image files'}, ...
        'Select reference image for ROI');
    if isequal(fname, 0)
        error('Image selection canceled.');
    end
    img_path = fullfile(fdir, fname);
end

function img = loadDisplayImage(img_path)
    img = imread(img_path);
    if ~ismatrix(img)
        img = img(:,:,1);
    end
    img = double(img);
    if isempty(img)
        error('Loaded image is empty: %s', img_path);
    end
end

function fov_x_um = estimateDefaultFovXUm(hSI, n_cols)
    fov_x_um = NaN;
    try
        zf = double(hSI.hRoiManager.scanZoomFactor);
        if isfinite(zf) && zf > 0 && exist('zoom2microns', 'file') == 2
            fov_x_um = double(zoom2microns(zf));
        end
    catch
    end
    if ~(isfinite(fov_x_um) && fov_x_um > 0)
        % Fallback to approximately 1 um/px based on image width if zoom is unavailable.
        fov_x_um = double(max(1, n_cols));
    end
end

function z_um = estimateCurrentZUm(hSI)
    z_um = 0;
    try
        pos = hSI.hMotors.samplePosition;
        if numel(pos) >= 3 && isfinite(pos(3))
            z_um = double(pos(3));
        end
    catch
    end
end

function settings = promptPrismSettings( ...
    fov_x_default, fov_y_default, h_default, zc_default, pdt_default, pf_default)

    prompts = { ...
        'FOV width X (um):', ...
        'FOV height Y (um):', ...
        'Prism height Z (um):', ...
        'Prism Z center (um):', ...
        'Pixel dwell (s):', ...
        'Power fraction [0..1]:'};
    defaults = { ...
        num2str(fov_x_default, '%.9g'), ...
        num2str(fov_y_default, '%.9g'), ...
        num2str(h_default, '%.9g'), ...
        num2str(zc_default, '%.9g'), ...
        num2str(pdt_default, '%.9g'), ...
        num2str(pf_default, '%.9g')};

    answer = inputdlg(prompts, 'Rectangular Prism Settings', [1 45], defaults);
    if isempty(answer)
        error('Settings prompt canceled.');
    end

    settings = struct();
    settings.fov_x_um = parseFinitePositive(answer{1}, 'FOV width X');
    settings.fov_y_um = parseFinitePositive(answer{2}, 'FOV height Y');
    settings.height_um = parseFinitePositive(answer{3}, 'Prism height Z');
    settings.z_center_um = parseFinite(answer{4}, 'Prism Z center');
    settings.pixel_dwell_s = parseFinitePositive(answer{5}, 'Pixel dwell');
    settings.power_fraction = parseFinite(answer{6}, 'Power fraction');

    assert(settings.power_fraction >= 0 && settings.power_fraction <= 1, ...
        'Power fraction must be in [0,1].');
end

function roi = selectRectangleRoiUm(img, fov_x_um, fov_y_um)
    x_min = -fov_x_um / 2;
    x_max =  fov_x_um / 2;
    y_min = -fov_y_um / 2;
    y_max =  fov_y_um / 2;

    fig = figure('Name', 'Select Rectangular ROI (double-click rectangle to finish)', ...
        'NumberTitle', 'off');
    ax = axes(fig);
    imagesc(ax, [x_min x_max], [y_min y_max], img);
    % Keep image-native orientation (row 1 at top) to avoid vertical flip.
    set(ax, 'YDir', 'reverse');
    axis(ax, 'image');
    xlabel(ax, 'X (um)');
    ylabel(ax, 'Y (um)');
    title(ax, 'Draw rectangle ROI, then double-click inside it');
    colormap(ax, gray(256));
    hold(ax, 'on');

    init_w = fov_x_um * 0.25;
    init_h = fov_y_um * 0.25;
    hRect = drawrectangle(ax, ...
        'Position', [-init_w/2, -init_h/2, init_w, init_h], ...
        'Color', [1 0 0], ...
        'FaceAlpha', 0.06, ...
        'LineWidth', 1.5);
    wait(hRect);

    pos = hRect.Position;
    close(fig);

    x0 = pos(1);
    y0 = pos(2);
    w = abs(pos(3));
    h = abs(pos(4));
    if w <= 0 || h <= 0
        error('ROI width/height must be positive.');
    end

    cx = x0 + pos(3)/2;
    cy_display = y0 + pos(4)/2;

    % Axes use image-native YDir='reverse' for correct visual orientation.
    % Convert display-Y back to scan-Y convention (+Y up in physical space).
    cy = cy_display;

    % Clamp center to field-of-view bounds if needed.
    cx = min(max(cx, x_min), x_max);
    cy = min(max(cy, y_min), y_max);

    roi = struct();
    roi.center_x_um = cx;
    roi.center_y_um = cy;
    roi.width_um = w;
    roi.length_um = h;
end

function [z_rel_um, x_templates, y_templates] = buildRectPrismLayerTemplates( ...
    width_x_um, length_y_um, height_z_um, spacing_x_um, spacing_y_um, spacing_z_um, z_sampling_mode)

    z_rel_um = buildRectZOffsets(height_z_um, spacing_z_um, z_sampling_mode);
    nL = numel(z_rel_um);
    x_templates = cell(nL,1);
    y_templates = cell(nL,1);

    x_half = width_x_um / 2;
    for li = 1:nL
        [x_templates{li}, y_templates{li}] = generateExtrudedLayerSnake( ...
            x_half, length_y_um, spacing_x_um, spacing_y_um);
    end
end

function z_rel_um = buildRectZOffsets(height_z_um, spacing_z_um, z_sampling_mode)
    half_z = height_z_um / 2;
    if half_z <= 0
        z_rel_um = 0;
        return;
    end

    switch lower(string(z_sampling_mode))
        case "grid_only"
            k_max = floor((half_z + 1e-12) / spacing_z_um);
            if k_max < 1
                z_rel_um = 0;
            else
                z_rel_um = (-k_max:k_max).' * spacing_z_um;
            end
        case "include_edges"
            z_rel_um = (-half_z:spacing_z_um:half_z).';
            z_rel_um = unique([z_rel_um; -half_z; 0; half_z]);
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

function plot_state = initLayerPlotRect( ...
    enable_plot, cx, cy, width_x_um, length_y_um, z_center_um, z_rel_um)

    plot_state = struct('enabled', false);
    if ~enable_plot
        return;
    end

    try
        fig = figure('Name', 'Rectangular Prism Layer Preview', 'NumberTitle', 'off');
        t = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        axXY = nexttile(t, 1);
        axXZ = nexttile(t, 2);

        % XY panel: ROI box + current layer path
        rectangle(axXY, 'Position', [cx - width_x_um/2, cy - length_y_um/2, width_x_um, length_y_um], ...
            'EdgeColor', [0.3 0.3 0.3], 'LineStyle', '--');
        hold(axXY, 'on');
        hXY = plot(axXY, nan, nan, 'b-', 'LineWidth', 1.0);
        hXYStart = plot(axXY, nan, nan, 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 5);
        hXYEnd = plot(axXY, nan, nan, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        hold(axXY, 'off');
        axis(axXY, 'equal');
        xlim(axXY, [cx - max(20, width_x_um*0.8), cx + max(20, width_x_um*0.8)]);
        ylim(axXY, [cy - max(20, length_y_um*0.8), cy + max(20, length_y_um*0.8)]);
        grid(axXY, 'on');
        xlabel(axXY, 'X (um)');
        ylabel(axXY, 'Y (um)');
        title(axXY, 'Current XY Beam Path');

        % XZ panel: planned layer centers
        layer_z_um = z_center_um + z_rel_um(:);
        scatter(axXZ, cx * ones(numel(layer_z_um), 1), layer_z_um, 12, [0.75 0.75 0.75], 'filled');
        hold(axXZ, 'on');
        hXZCurrent = plot(axXZ, nan, nan, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        hXZSpan = plot(axXZ, nan, nan, 'r-', 'LineWidth', 1.5);
        hold(axXZ, 'off');
        x_margin = max(5, 0.1 * max(1, width_x_um));
        z_span = max(1, range(layer_z_um));
        z_margin = max(2, 0.1 * z_span);
        xlim(axXZ, [cx - width_x_um/2 - x_margin, cx + width_x_um/2 + x_margin]);
        ylim(axXZ, [min(layer_z_um)-z_margin, max(layer_z_um)+z_margin]);
        grid(axXZ, 'on');
        xlabel(axXZ, 'X (um)');
        ylabel(axXZ, 'Z (um)');
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
        warning('ablate_rect_prism_gui:PlotInitFailed', ...
            'Layer plotting disabled: %s', ME.message);
        plot_state = struct('enabled', false);
    end
end

function updateLayerPlot(plot_state, x_play, y_play, z_target_um, layer_idx, n_layers, decim, pause_s)
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
    title(plot_state.axXY, sprintf('Current XY Beam Path | layer %d/%d | Z=%.3f um', ...
        layer_idx, n_layers, z_target_um));

    set(plot_state.hXZCurrent, 'XData', mean(x_play), 'YData', z_target_um);
    set(plot_state.hXZSpan, 'XData', [min(x_play), max(x_play)], ...
        'YData', [z_target_um, z_target_um]);

    drawnow limitrate;
    if pause_s > 0
        pause(pause_s);
    end
end

function runCaptureGrabBlocking(~)
    return
end

function timing_est = estimateRunTiming( ...
    pixel_dwell_s, z_rel_um, x_templates, y_templates, ...
    lead_in_s, tail_out_s, turn_blanking, turn_angle_deg, turn_blank_s, ...
    z_settle_s, z_move_tol_um, z_center_um)

    n_layers = numel(z_rel_um);
    points_per_layer = zeros(n_layers, 1);
    sharp_turns_per_layer = zeros(n_layers, 1);
    for li = 1:n_layers
        points_per_layer(li) = numel(x_templates{li});
        if turn_blanking && turn_blank_s > 0
            sharp_turns_per_layer(li) = countSharpTurns( ...
                x_templates{li}, y_templates{li}, turn_angle_deg);
        end
    end

    dwell_s = sum(points_per_layer) * pixel_dwell_s;
    lead_tail_s = n_layers * (lead_in_s + tail_out_s);
    turn_blank_total_s = sum(sharp_turns_per_layer) * turn_blank_s;

    z_layers = z_center_um + z_rel_um;
    z_move_count = countPlannedZMoves(z_layers, z_move_tol_um);
    z_settle_total_s = z_move_count * z_settle_s;

    nominal_s = dwell_s + lead_tail_s + turn_blank_total_s + z_settle_total_s;
    eta_nominal = datetime('now') + seconds(nominal_s);
    eta_nominal.Format = 'yyyy-MM-dd HH:mm:ss';

    timing_est = struct( ...
        'dwell_s', dwell_s, ...
        'lead_tail_s', lead_tail_s, ...
        'turn_blank_s', turn_blank_total_s, ...
        'z_settle_s', z_settle_total_s, ...
        'nominal_s', nominal_s, ...
        'eta_nominal', eta_nominal);
end

function n_moves = countPlannedZMoves(z_layers, z_move_tol_um)
    n_moves = 0;
    last_z = NaN;
    for li = 1:numel(z_layers)
        z_target = z_layers(li);
        if isnan(last_z) || abs(z_target - last_z) > z_move_tol_um
            n_moves = n_moves + 1;
            last_z = z_target;
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

function v = parseFinitePositive(raw, label)
    v = parseFinite(raw, label);
    if ~(v > 0)
        error('%s must be > 0.', label);
    end
end

function v = parseFinite(raw, label)
    v = str2double(strtrim(raw));
    if ~(isfinite(v))
        error('Invalid numeric value for %s.', label);
    end
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
