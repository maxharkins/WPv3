% Frame-scan ablation + imaging sequence (minimal)
%
% For each z:
%   1) Ablation grab (acquire, do not save)
%   2) Imaging grab (acquire and save)
%
% Per grab this script sets only:
%   - zoom (setZoomFactor)
%   - pixelsPerLine
%   - linesPerFrame
%   - pixel dwell (via GUI callback path)
%   - beam power fraction

%% ========================= USER CONFIG =========================

% Ablation settings (physical targeting)
ablation_width_um      = 120;
ablation_height_um     = 20;
ablation_beam_waist_um = 0.79;    % one pixel per beam waist
ablation_pixel_dwell_s = 1e-3;
Pf_ablation            = 1.0;

% Imaging settings
imaging_pixels_per_line = 1024;
imaging_lines_per_frame = 1024;
imaging_pixel_dwell_s   = 3200e-9;
Pf_imaging              = 0.25;

% Imaging zoom options:
% - If true, zoom is computed from target FOV via microns2zoom().
% - If false, imaging_zoom_factor is used directly.
imaging_use_target_fov_um = true;
imaging_target_fov_um     = 300;
imaging_zoom_factor       = 5.0;

% Optional FOV shift (ScanImage scanner-angle units, not um)
apply_fov_shift = true;
fov_shift_mode  = 'absolute';   % 'absolute' or 'relative'
fov_shift_fast  = 0;
fov_shift_slow  = 0;

% Z positions (um), scalar or vector
zs = 100;

% Save settings (imaging only)
save_dir = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-03-31_surface-ablations\raw";
experiment_label = 'exp_005';

% Timing
zoom_settle_s   = 0.10;
move_settle_s   = 0.50;
between_grabs_s = 0.50;

% Behavior
save_ablation_grab = false;   % false = ablation acquires but is not saved
leave_beam_off_at_end = true;

%% ======================= END USER CONFIG =======================

assert(exist('microns2zoom', 'file') == 2 || exist('microns2zoom', 'builtin') == 5, ...
    'microns2zoom.m not found on MATLAB path.');
assert(exist('configure_grab_basename', 'file') == 2, ...
    'configure_grab_basename.m not found on MATLAB path.');
assert(exist('grab_and_save_with_metadata', 'file') == 2, ...
    'grab_and_save_with_metadata.m not found on MATLAB path.');

% Derived ablation raster from physical targeting
ablation_pixels_per_line = max(4, round(ablation_width_um / ablation_beam_waist_um));
ablation_lines_per_frame = max(2, round(ablation_height_um / ablation_beam_waist_um));
ablation_target_fov_um   = ablation_pixels_per_line * ablation_beam_waist_um;

ablation_zoom_factor = double(microns2zoom(ablation_target_fov_um));
if imaging_use_target_fov_um
    imaging_zoom_factor = double(microns2zoom(imaging_target_fov_um));
end

% Helpful snap info (physical request snapped to integer pixels)
ablation_width_um_snap  = ablation_pixels_per_line * ablation_beam_waist_um;
ablation_height_um_snap = ablation_lines_per_frame * ablation_beam_waist_um;

% Resolve hSI/hSICtl
if exist('hWP', 'var') && ~isempty(hWP)
    hSI = hWP.hSI;
elseif exist('hSI', 'var') && ~isempty(hSI)
    % local hSI
elseif evalin('base', 'exist(''hWP'',''var'')')
    hWP = evalin('base', 'hWP');
    hSI = hWP.hSI;
elseif evalin('base', 'exist(''hSI'',''var'')')
    hSI = evalin('base', 'hSI');
else
    error('Could not find hWP/hSI in local/base workspace.');
end

if exist('hSICtl', 'var') && ~isempty(hSICtl)
    % local hSICtl
elseif evalin('base', 'exist(''hSICtl'',''var'')')
    hSICtl = evalin('base', 'hSICtl');
else
    hSICtl = [];
    try
        hSICtl = hSI.hController;
    catch
    end
end

assert(isvalid(hSI), 'hSI handle is invalid.');
assert(~isempty(hSICtl) && isvalid(hSICtl), ...
    'Could not resolve a valid hSICtl handle.');
assert(~isempty(hSI.hScan2D.hBeams), 'No beams found at hSI.hScan2D.hBeams.');
beam = hSI.hScan2D.hBeams{1};

% Frame mode only
try
    hSI.hRoiManager.scanType = 'frame';
catch
end

if apply_fov_shift
    applyFovShift(hSI, fov_shift_fast, fov_shift_slow, fov_shift_mode);
end

fprintf('\nPlanned settings:\n');
fprintf('  Ablation: zoom %.3f, %d x %d, PDT %.3g s, beam %.3f\n', ...
    ablation_zoom_factor, ablation_pixels_per_line, ablation_lines_per_frame, ...
    ablation_pixel_dwell_s, Pf_ablation);
fprintf('            requested %.3f x %.3f um, snapped %.3f x %.3f um\n', ...
    ablation_width_um, ablation_height_um, ablation_width_um_snap, ablation_height_um_snap);
fprintf('  Imaging : zoom %.3f, %d x %d, PDT %.3g s, beam %.3f\n\n', ...
    imaging_zoom_factor, imaging_pixels_per_line, imaging_lines_per_frame, ...
    imaging_pixel_dwell_s, Pf_imaging);

results = repmat(struct('z_um', nan, 'ablation', [], 'imaging', []), numel(zs), 1);

for zIdx = 1:numel(zs)
    z = zs(zIdx);
    fprintf('z #%d/%d: %.3f um\n', zIdx, numel(zs), z);

    hSI.hMotors.moveSampleNoQuery([NaN, NaN, z], true);
    pause(move_settle_s);

    % -------- Ablation grab (not saved by default) --------
    abl = applyGrabSettings( ...
        hSI, hSICtl, beam, ...
        ablation_zoom_factor, ...
        ablation_pixels_per_line, ...
        ablation_lines_per_frame, ...
        ablation_pixel_dwell_s, ...
        Pf_ablation, ...
        zoom_settle_s);

    fprintf('  Ablation: zoom %.3f->%.3f, %d x %d, PDT %.3g->%.3g s, pixel %.6f um\n', ...
        ablation_zoom_factor, abl.zoom_actual, abl.pixels_per_line, abl.lines_per_frame, ...
        ablation_pixel_dwell_s, abl.pdt_actual_s, abl.pixel_um);

    if save_ablation_grab
        stemA = sprintf('%s_z%s_ablation', experiment_label, zToStem(z));
        cfgA = configure_grab_basename(save_dir, stemA, ...
            'HSI', hSI, ...
            'UserMetadata', struct( ...
                'experiment', experiment_label, ...
                'grab_type', 'ablation', ...
                'z_um', z, ...
                'zoom_factor_target', ablation_zoom_factor, ...
                'zoom_factor_actual', abl.zoom_actual, ...
                'pixels_per_line', abl.pixels_per_line, ...
                'lines_per_frame', abl.lines_per_frame, ...
                'pixel_dwell_target_s', ablation_pixel_dwell_s, ...
                'pixel_dwell_actual_s', abl.pdt_actual_s, ...
                'pixel_um', abl.pixel_um, ...
                'beam_power_fraction', abl.beam_power_actual));
        outA = doGrab(hSI, true, cfgA);
    else
        outA = doGrab(hSI, false, []);
    end

    pause(between_grabs_s);

    % -------- Imaging grab (saved) --------
    img = applyGrabSettings( ...
        hSI, hSICtl, beam, ...
        imaging_zoom_factor, ...
        imaging_pixels_per_line, ...
        imaging_lines_per_frame, ...
        imaging_pixel_dwell_s, ...
        Pf_imaging, ...
        zoom_settle_s);

    fprintf('  Imaging : zoom %.3f->%.3f, %d x %d, PDT %.3g->%.3g s, pixel %.6f um\n', ...
        imaging_zoom_factor, img.zoom_actual, img.pixels_per_line, img.lines_per_frame, ...
        imaging_pixel_dwell_s, img.pdt_actual_s, img.pixel_um);

    stemI = sprintf('%s_z%s_imaging', experiment_label, zToStem(z));
    cfgI = configure_grab_basename(save_dir, stemI, ...
        'HSI', hSI, ...
        'UserMetadata', struct( ...
            'experiment', experiment_label, ...
            'grab_type', 'imaging', ...
            'z_um', z, ...
            'zoom_factor_target', imaging_zoom_factor, ...
            'zoom_factor_actual', img.zoom_actual, ...
            'pixels_per_line', img.pixels_per_line, ...
            'lines_per_frame', img.lines_per_frame, ...
            'pixel_dwell_target_s', imaging_pixel_dwell_s, ...
            'pixel_dwell_actual_s', img.pdt_actual_s, ...
            'pixel_um', img.pixel_um, ...
            'beam_power_fraction', img.beam_power_actual));
    outI = doGrab(hSI, true, cfgI);

    results(zIdx).z_um = z;
    results(zIdx).ablation = struct('settings', abl, 'output', outA, 'saved', logical(save_ablation_grab));
    results(zIdx).imaging = struct('settings', img, 'output', outI, 'saved', true);

    pause(between_grabs_s);
end

if leave_beam_off_at_end
    setBeamPowerFrac(hSI, beam, 0);
end

assignin('base', 'ablation_imaging_results', results);
fprintf('Done.\n');

function s = applyGrabSettings( ...
    hSI, hSICtl, beam, zoom_target, pixels_per_line, lines_per_frame, pdt_target_s, pf, zoom_settle_s)

    validateattributes(zoom_target, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(pixels_per_line, {'numeric'}, {'scalar', 'finite', 'integer', '>=', 1});
    validateattributes(lines_per_frame, {'numeric'}, {'scalar', 'finite', 'integer', '>=', 1});
    validateattributes(pdt_target_s, {'numeric'}, {'scalar', 'finite', 'positive'});

    setZoomFactor(hSICtl, zoom_target);
    if zoom_settle_s > 0
        pause(zoom_settle_s);
    end

    hSI.hRoiManager.pixelsPerLine = round(pixels_per_line);
    hSI.hRoiManager.linesPerFrame = round(lines_per_frame);

    setPixelDwellViaCallback(hSICtl, pdt_target_s);
    setBeamPowerFrac(hSI, beam, pf);

    s = struct();
    s.zoom_target = zoom_target;
    s.zoom_actual = nan;
    s.pixels_per_line = nan;
    s.lines_per_frame = nan;
    s.pdt_target_s = pdt_target_s;
    s.pdt_actual_s = nan;
    s.fov_um = nan;
    s.height_um = nan;
    s.pixel_um = nan;
    s.beam_power_target = pf;
    s.beam_power_actual = nan;

    try, s.zoom_actual = double(hSI.hRoiManager.scanZoomFactor); catch, end
    try, s.pixels_per_line = double(hSI.hRoiManager.pixelsPerLine); catch, end
    try, s.lines_per_frame = double(hSI.hRoiManager.linesPerFrame); catch, end
    try, s.pdt_actual_s = double(hSI.hScan2D.scanPixelTimeMean); catch, end
    s.beam_power_actual = getBeamPowerFrac(hSI, beam);

    [s.fov_um, s.height_um, s.pixel_um] = estimateGeometryFromZoom(s.zoom_actual, s.pixels_per_line, s.lines_per_frame);
end

function setPixelDwellViaCallback(hSICtl, pdt_target_s)
    target_ns = pdt_target_s * 1e9;

    try
        g = hSICtl.hGUIData.configControlsV4;
        try, g.pmScanRateVar.Value = 1; catch, end % Pixel Dwell Time mode
        try, hSICtl.changedLineRateVar(); catch, end
        try, set(g.etLineRate, 'String', num2str(target_ns, '%.9g')); catch, end
        hSICtl.setLineRate(g.etLineRate, target_ns);
    catch
        % Fallback for setups without the GUI callback path
        try
            hSI = hSICtl.hModel;
            hSI.hRoiManager.linePeriod = pdt_target_s * double(hSI.hRoiManager.pixelsPerLine);
        catch
            warning('Unable to set pixel dwell time by callback or fallback linePeriod.');
        end
    end
end

function out = doGrab(hSI, do_save, cfg)
    waitForIdle(hSI);

    prevSave = logical(hSI.hChannels.loggingEnable);
    if do_save
        hSI.hChannels.loggingEnable = true;
    else
        hSI.hChannels.loggingEnable = false;
    end
    cleanupObj = onCleanup(@()restoreLogging(hSI, prevSave)); %#ok<NASGU>

    if do_save
        out = grab_and_save_with_metadata('HSI', hSI, 'Config', cfg);
    else
        hSI.startGrab();
        waitForIdle(hSI);
        out = struct('saved', false, 'note', 'Grab acquired with logging disabled.');
    end
end

function waitForIdle(hSI)
    timeout_s = 120;
    t0 = tic;
    while ~strcmpi(hSI.acqState, 'idle')
        if toc(t0) > timeout_s
            error('Timed out waiting for ScanImage to become idle. Current state: %s', hSI.acqState);
        end
        pause(0.02);
    end
end

function restoreLogging(hSI, prevSave)
    try
        hSI.hChannels.loggingEnable = prevSave;
    catch
    end
end

function [fov_um, height_um, pixel_um] = estimateGeometryFromZoom(zoom_factor, ppl, lpf)
    fov_um = nan;
    height_um = nan;
    pixel_um = nan;

    if ~(isfinite(zoom_factor) && isfinite(ppl) && isfinite(lpf) && ppl > 0 && lpf > 0)
        return;
    end

    try
        fov_um = double(zoom2microns(zoom_factor));
        height_um = fov_um * (lpf / ppl);
        pixel_um = fov_um / ppl;
    catch
    end
end

function applyFovShift(hSI, shift_fast, shift_slow, mode)
    switch lower(string(mode))
        case "relative"
            hSI.hRoiManager.scanAngleShiftFast = hSI.hRoiManager.scanAngleShiftFast + shift_fast;
            hSI.hRoiManager.scanAngleShiftSlow = hSI.hRoiManager.scanAngleShiftSlow + shift_slow;
        case "absolute"
            hSI.hRoiManager.scanAngleShiftFast = shift_fast;
            hSI.hRoiManager.scanAngleShiftSlow = shift_slow;
        otherwise
            error('fov_shift_mode must be ''absolute'' or ''relative''.');
    end
end

function setBeamPowerFrac(hSI, beam, pf)
    pf = max(0, min(1, double(pf)));
    set_ok = false;

    try
        beam.setPowerFraction(pf);
        set_ok = true;
    catch
    end
    try
        beam.powerFraction = pf;
        set_ok = true;
    catch
    end
    try
        if isprop(hSI, 'hBeams') && isprop(hSI.hBeams, 'powerFractions')
            pfs = hSI.hBeams.powerFractions;
            if isempty(pfs)
                hSI.hBeams.powerFractions = pf;
            else
                pfs(1) = pf;
                hSI.hBeams.powerFractions = pfs;
            end
            set_ok = true;
        end
    catch
    end

    if ~set_ok
        warning('Unable to set beam power fraction.');
    end
end

function pf = getBeamPowerFrac(hSI, beam)
    pf = nan;
    try, pf = double(beam.powerFraction); catch, end
    if ~isfinite(pf)
        try
            if isprop(hSI, 'hBeams') && isprop(hSI.hBeams, 'powerFractions')
                pfs = double(hSI.hBeams.powerFractions);
                if ~isempty(pfs)
                    pf = pfs(1);
                end
            end
        catch
        end
    end
end

function out = zToStem(z)
    out = sprintf('%.3f', z);
    out = strrep(out, '-', 'm');
    out = strrep(out, '.', 'p');
end
