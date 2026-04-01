Updated and saved at [frame_scan_ablation_imaging_grabs.m](/Users/maxharkins/Documents/Research%20-%20Zhang%20%26%20Brown%20Labs/ScanImage_tailored/frame_scan_ablation_imaging_grabs.m).

```matlab
% Frame-scan ablation + imaging grabs (no custom raster/path playback)
%
% Quick use:
% 1) Edit the USER CONFIG section.
% 2) Run this script.
% 3) For each z, it runs two GRABs:
%       - ablation grab
%       - imaging grab
%
% This script sets, before each grab:
%   - zoom factor with: setZoomFactor(hSICtl, targetZoomFactor)
%   - pixelsPerLine
%   - linesPerFrame
%   - pixel dwell time (best achievable)
%   - beam power fraction

%% ========================= USER CONFIG =========================

% Ablation grab settings (physical targeting)
ablation_width_um      = 120;    % target width in sample plane
ablation_height_um     = 20;     % target height in sample plane
ablation_beam_waist_um = 0.79;   % one pixel per beam waist
ablation_pixel_dwell_s = 2e-6;
Pf_ablation            = 0.70;

% Imaging grab settings
imaging_pixels_per_line = 512;
imaging_lines_per_frame = 512;
imaging_pixel_dwell_s   = 1e-6;
Pf_imaging              = 0.10;

% Imaging zoom options:
% - If imaging_use_target_fov_um = true, zoom is computed by microns2zoom().
% - Otherwise imaging_zoom_factor is used directly.
imaging_use_target_fov_um = false;
imaging_target_fov_um     = 300;
imaging_zoom_factor       = 4.0;

% Optional FOV shift (ScanImage scanner-angle units, not um)
apply_fov_shift = true;
fov_shift_mode  = 'absolute';   % 'absolute' or 'relative'
fov_shift_fast  = 0;
fov_shift_slow  = 0;

% Z positions (um), scalar or vector
zs = 100;

% Save settings
save_dir = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-03-31_surface-ablations\raw";
experiment_label = 'exp_004';

% Timing/behavior
zoom_settle_s = 0.10;
move_settle_s = 0.50;
between_grabs_s = 0.50;

% If true: restore scan settings on exit (even on error)
restore_original_scan_state = true;

% Only applies when restore_original_scan_state == false
leave_beam_off_at_end = true;

%% ======================= END USER CONFIG =======================

% Derive ablation frame settings from physical targets.
ablation_pixels_per_line = max(4, round(ablation_width_um / ablation_beam_waist_um));
ablation_lines_per_frame = max(2, round(ablation_height_um / ablation_beam_waist_um));
ablation_target_fov_um = ablation_pixels_per_line * ablation_beam_waist_um;

try
    ablation_zoom_factor = double(microns2zoom(ablation_target_fov_um));
catch ME
    error(['microns2zoom() failed for ablation settings. ' ...
           'Make sure microns2zoom is on your MATLAB path. Details: %s'], ME.message);
end

if imaging_use_target_fov_um
    try
        imaging_zoom_factor = double(microns2zoom(imaging_target_fov_um));
    catch ME
        error(['microns2zoom() failed for imaging settings. ' ...
               'Make sure microns2zoom is on your MATLAB path. Details: %s'], ME.message);
    end
end

ablation_fov_um_actual = safeZoom2Microns(ablation_zoom_factor);
imaging_fov_um_actual = safeZoom2Microns(imaging_zoom_factor);

ablation_height_um_actual = ablation_fov_um_actual * (ablation_lines_per_frame / ablation_pixels_per_line);
imaging_height_um_actual = imaging_fov_um_actual * (imaging_lines_per_frame / imaging_pixels_per_line);

assert(exist('configure_grab_basename', 'file') == 2, ...
    'configure_grab_basename.m not found on MATLAB path.');
assert(exist('grab_and_save_with_metadata', 'file') == 2, ...
    'grab_and_save_with_metadata.m not found on MATLAB path.');

% Resolve hSI
if exist('hWP', 'var') && ~isempty(hWP)
    hSI = hWP.hSI;
elseif exist('hSI', 'var') && ~isempty(hSI)
    % use local hSI
elseif evalin('base', 'exist(''hWP'',''var'')')
    hWP = evalin('base', 'hWP');
    hSI = hWP.hSI;
elseif evalin('base', 'exist(''hSI'',''var'')')
    hSI = evalin('base', 'hSI');
else
    error('Could not find hWP or hSI in local/base workspace.');
end

% Resolve hSICtl (needed for setZoomFactor)
if exist('hSICtl', 'var') && ~isempty(hSICtl)
    % use local hSICtl
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
    'Could not resolve a valid hSICtl handle (required for setZoomFactor).');
assert(~isempty(hSI.hScan2D.hBeams), 'No beams found at hSI.hScan2D.hBeams.');
beam = hSI.hScan2D.hBeams{1};

prev = snapshotState(hSI, beam);
if restore_original_scan_state
    cleanupObj = onCleanup(@()restoreState(hSI, hSICtl, beam, prev)); %#ok<NASGU>
end

try
    hSI.hRoiManager.scanType = 'frame';
catch
end

if apply_fov_shift
    applyFovShift(hSI, fov_shift_fast, fov_shift_slow, fov_shift_mode);
end

results = repmat(struct('z_um', nan, 'ablation', [], 'imaging', []), numel(zs), 1);

fprintf('\nPlanned settings:\n');
fprintf('  Ablation: zoom %.3f, %d x %d px, target %.2f x %.2f um, estimated %.2f x %.2f um\n', ...
    ablation_zoom_factor, ...
    ablation_pixels_per_line, ablation_lines_per_frame, ...
    ablation_width_um, ablation_height_um, ...
    ablation_fov_um_actual, ablation_height_um_actual);
fprintf('  Imaging : zoom %.3f, %d x %d px, estimated %.2f x %.2f um\n\n', ...
    imaging_zoom_factor, ...
    imaging_pixels_per_line, imaging_lines_per_frame, ...
    imaging_fov_um_actual, imaging_height_um_actual);

fprintf('Starting frame-scan ablation/imaging sequence...\n');

for zIdx = 1:numel(zs)
    z = zs(zIdx);
    fprintf('z #%d/%d: %.3f um\n', zIdx, numel(zs), z);

    hSI.hMotors.moveSampleNoQuery([NaN, NaN, z], true);
    pause(move_settle_s);

    % -------- Ablation grab --------
    setBeamPowerFrac(beam, Pf_ablation);
    [zoomA_actual, pdtA_actual] = applyGrabScanSettings( ...
        hSI, hSICtl, ...
        ablation_zoom_factor, ...
        ablation_pixels_per_line, ...
        ablation_lines_per_frame, ...
        ablation_pixel_dwell_s, ...
        zoom_settle_s);

    fprintf('  Ablation: zoom %.3f -> %.3f, %d x %d, PDT %.3g -> %.3g s\n', ...
        ablation_zoom_factor, zoomA_actual, ...
        ablation_pixels_per_line, ablation_lines_per_frame, ...
        ablation_pixel_dwell_s, pdtA_actual);

    stemA = sprintf('%s_z%s_ablation', experiment_label, zToStem(z));
    cfgA = configure_grab_basename(save_dir, stemA, ...
        'HSI', hSI, ...
        'UserMetadata', struct( ...
            'experiment', experiment_label, ...
            'grab_type', 'ablation', ...
            'z_um', z, ...
            'zoom_factor_target', ablation_zoom_factor, ...
            'zoom_factor_actual', zoomA_actual, ...
            'target_width_um', ablation_width_um, ...
            'target_height_um', ablation_height_um, ...
            'estimated_fov_um', ablation_fov_um_actual, ...
            'estimated_height_um', ablation_height_um_actual, ...
            'pixels_per_line', ablation_pixels_per_line, ...
            'lines_per_frame', ablation_lines_per_frame, ...
            'pixel_dwell_target_s', ablation_pixel_dwell_s, ...
            'pixel_dwell_actual_s', pdtA_actual, ...
            'beam_power_fraction', Pf_ablation, ...
            'scan_shift_fast', hSI.hRoiManager.scanAngleShiftFast, ...
            'scan_shift_slow', hSI.hRoiManager.scanAngleShiftSlow));
    outA = grab_and_save_with_metadata('HSI', hSI, 'Config', cfgA);

    pause(between_grabs_s);

    % -------- Imaging grab --------
    setBeamPowerFrac(beam, Pf_imaging);
    [zoomI_actual, pdtI_actual] = applyGrabScanSettings( ...
        hSI, hSICtl, ...
        imaging_zoom_factor, ...
        imaging_pixels_per_line, ...
        imaging_lines_per_frame, ...
        imaging_pixel_dwell_s, ...
        zoom_settle_s);

    fprintf('  Imaging : zoom %.3f -> %.3f, %d x %d, PDT %.3g -> %.3g s\n', ...
        imaging_zoom_factor, zoomI_actual, ...
        imaging_pixels_per_line, imaging_lines_per_frame, ...
        imaging_pixel_dwell_s, pdtI_actual);

    stemI = sprintf('%s_z%s_imaging', experiment_label, zToStem(z));
    cfgI = configure_grab_basename(save_dir, stemI, ...
        'HSI', hSI, ...
        'UserMetadata', struct( ...
            'experiment', experiment_label, ...
            'grab_type', 'imaging', ...
            'z_um', z, ...
            'zoom_factor_target', imaging_zoom_factor, ...
            'zoom_factor_actual', zoomI_actual, ...
            'estimated_fov_um', imaging_fov_um_actual, ...
            'estimated_height_um', imaging_height_um_actual, ...
            'pixels_per_line', imaging_pixels_per_line, ...
            'lines_per_frame', imaging_lines_per_frame, ...
            'pixel_dwell_target_s', imaging_pixel_dwell_s, ...
            'pixel_dwell_actual_s', pdtI_actual, ...
            'beam_power_fraction', Pf_imaging, ...
            'scan_shift_fast', hSI.hRoiManager.scanAngleShiftFast, ...
            'scan_shift_slow', hSI.hRoiManager.scanAngleShiftSlow));
    outI = grab_and_save_with_metadata('HSI', hSI, 'Config', cfgI);

    results(zIdx).z_um = z;
    results(zIdx).ablation = struct( ...
        'output', outA, ...
        'zoom_target', ablation_zoom_factor, ...
        'zoom_actual', zoomA_actual, ...
        'pdt_target_s', ablation_pixel_dwell_s, ...
        'pdt_actual_s', pdtA_actual);
    results(zIdx).imaging = struct( ...
        'output', outI, ...
        'zoom_target', imaging_zoom_factor, ...
        'zoom_actual', zoomI_actual, ...
        'pdt_target_s', imaging_pixel_dwell_s, ...
        'pdt_actual_s', pdtI_actual);

    pause(between_grabs_s);
end

if leave_beam_off_at_end && ~restore_original_scan_state
    setBeamPowerFrac(beam, 0);
end

assignin('base', 'ablation_imaging_results', results);
fprintf('Done.\n');

function [zoom_actual, pdt_actual] = applyGrabScanSettings( ...
    hSI, hSICtl, zoom_target, pixels_per_line, lines_per_frame, pdt_target_s, zoom_settle_s)

    zoom_actual = setZoomWithController(hSI, hSICtl, zoom_target, zoom_settle_s);
    pdt_actual = applyFrameTiming(hSI, pixels_per_line, lines_per_frame, pdt_target_s);
end

function zoom_actual = setZoomWithController(hSI, hSICtl, zoom_target, zoom_settle_s)
    validateattributes(zoom_target, {'numeric'}, {'scalar', 'finite', 'positive'});
    try
        setZoomFactor(hSICtl, zoom_target);
    catch ME
        error('setZoomFactor(hSICtl, targetZoomFactor) failed: %s', ME.message);
    end

    if zoom_settle_s > 0
        pause(zoom_settle_s);
    end

    zoom_actual = nan;
    try
        zoom_actual = double(hSI.hRoiManager.scanZoomFactor);
    catch
    end
end

function pdt_actual = applyFrameTiming(hSI, pixels_per_line, lines_per_frame, pdt_target_s)
    validateattributes(pixels_per_line, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(lines_per_frame, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(pdt_target_s, {'numeric'}, {'scalar', 'finite', 'positive'});

    hSI.hRoiManager.pixelsPerLine = round(pixels_per_line);
    hSI.hRoiManager.linesPerFrame = round(lines_per_frame);

    hScan = hSI.hScan2D;
    applied = false;

    % Best-effort dwell setting via sampleRate/pixelBinFactor
    try
        rates = [];
        if isprop(hScan, 'validSampleRates')
            rates = double(hScan.validSampleRates);
        end
        if isempty(rates) && isprop(hScan, 'sampleRate')
            rates = double(hScan.sampleRate);
        end

        rates = rates(isfinite(rates) & rates > 0);
        if ~isempty(rates) && isprop(hScan, 'pixelBinFactor')
            bestErr = inf;
            bestRate = nan;
            bestBin = nan;
            for i = 1:numel(rates)
                r = rates(i);
                b = max(1, round(pdt_target_s * r));
                pdt = b / r;
                err = abs(pdt - pdt_target_s);
                if err < bestErr
                    bestErr = err;
                    bestRate = r;
                    bestBin = b;
                end
            end

            if isfinite(bestRate) && isfinite(bestBin)
                try
                    if isprop(hScan, 'sampleRate')
                        hScan.sampleRate = bestRate;
                    end
                catch
                end
                try
                    hScan.pixelBinFactor = bestBin;
                    applied = true;
                catch
                end
            end
        end
    catch
    end

    % Fallback: linePeriod = pixelDwell * pixelsPerLine
    if ~applied
        try
            hSI.hRoiManager.linePeriod = pdt_target_s * double(hSI.hRoiManager.pixelsPerLine);
            applied = true;
        catch
        end
    end

    pdt_actual = nan;
    try
        pdt_actual = double(hSI.hScan2D.scanPixelTimeMean);
    catch
    end

    if ~applied
        warning('Could not set dwell time on this scan mode/hardware. Using current timing.');
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

function setBeamPowerFrac(beam, pf)
    pf = max(0, min(1, double(pf)));
    try
        beam.setPowerFraction(pf);
    catch
        try
            beam.powerFraction = pf;
        catch
            warning('Unable to set beam power fraction on beam handle.');
        end
    end
end

function out = zToStem(z)
    out = sprintf('%.3f', z);
    out = strrep(out, '-', 'm');
    out = strrep(out, '.', 'p');
end

function fov_um = safeZoom2Microns(zoom_factor)
    fov_um = nan;
    try
        fov_um = double(zoom2microns(zoom_factor));
    catch
    end
end

function s = snapshotState(hSI, beam)
    s = struct();
    s.scanType = '';
    s.scanZoomFactor = nan;
    s.pixelsPerLine = nan;
    s.linesPerFrame = nan;
    s.linePeriod = nan;
    s.sampleRate = nan;
    s.pixelBinFactor = nan;
    s.scanAngleShiftFast = nan;
    s.scanAngleShiftSlow = nan;
    s.beamPowerFraction = nan;

    try, s.scanType = hSI.hRoiManager.scanType; catch, end
    try, s.scanZoomFactor = double(hSI.hRoiManager.scanZoomFactor); catch, end
    try, s.pixelsPerLine = double(hSI.hRoiManager.pixelsPerLine); catch, end
    try, s.linesPerFrame = double(hSI.hRoiManager.linesPerFrame); catch, end
    try, s.linePeriod = double(hSI.hRoiManager.linePeriod); catch, end
    try, s.sampleRate = double(hSI.hScan2D.sampleRate); catch, end
    try, s.pixelBinFactor = double(hSI.hScan2D.pixelBinFactor); catch, end
    try, s.scanAngleShiftFast = double(hSI.hRoiManager.scanAngleShiftFast); catch, end
    try, s.scanAngleShiftSlow = double(hSI.hRoiManager.scanAngleShiftSlow); catch, end
    try, s.beamPowerFraction = double(beam.powerFraction); catch, end
end

function restoreState(hSI, hSICtl, beam, s)
    try, hSI.hRoiManager.scanType = s.scanType; catch, end
    if isfinite(s.scanZoomFactor)
        try
            setZoomFactor(hSICtl, s.scanZoomFactor);
        catch
            try, hSI.hRoiManager.scanZoomFactor = s.scanZoomFactor; catch, end
        end
    end
    try, hSI.hRoiManager.pixelsPerLine = s.pixelsPerLine; catch, end
    try, hSI.hRoiManager.linesPerFrame = s.linesPerFrame; catch, end
    try, hSI.hRoiManager.linePeriod = s.linePeriod; catch, end
    try, hSI.hScan2D.sampleRate = s.sampleRate; catch, end
    try, hSI.hScan2D.pixelBinFactor = s.pixelBinFactor; catch, end
    try, hSI.hRoiManager.scanAngleShiftFast = s.scanAngleShiftFast; catch, end
    try, hSI.hRoiManager.scanAngleShiftSlow = s.scanAngleShiftSlow; catch, end
    try, setBeamPowerFrac(beam, s.beamPowerFraction); catch, end
end
```