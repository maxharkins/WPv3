% Frame-scan ablation + imaging grabs (no custom raster/path playback)
%
% This script runs TWO grabs at each z:
%   1) ablation grab (frame scan settings A)
%   2) imaging grab  (frame scan settings B)
%
% It controls:
%   - pixels per line
%   - lines per frame
%   - pixel dwell time (via sampleRate/pixelBinFactor when supported)
%   - optional FOV shift (scanAngleShiftFast/Slow)

%% ablation scan config
ablation_pixels_per_line = 512;   % pixels
ablation_lines_per_frame = 64;    % lines
ablation_pixel_dwell_s = 2e-6;    % seconds
Pf_ablation = 0.70;               % beam power fraction (0..1)

%% imaging scan config
imaging_pixels_per_line = 512;    % pixels
imaging_lines_per_frame = 512;    % lines
imaging_pixel_dwell_s = 1e-6;     % seconds
Pf_imaging = 0.10;                % beam power fraction (0..1)

%% optional FOV shift
apply_fov_shift = true;
fov_shift_mode = 'absolute';      % 'absolute' or 'relative'
fov_shift_fast = 0;               % scanner-angle units (not um)
fov_shift_slow = 0;               % scanner-angle units (not um)

%% z config
zs = 100;                         % um (scalar or vector)

%% save config
save_dir = "C:\Users\SCIENTIFICA\Box\Zhang&Brown\Experiments\2026\2026-03-31_surface-ablations\raw";
experiment_label = 'exp_004';

%% behavior
move_settle_s = 0.5;              % seconds
between_grabs_s = 0.5;            % seconds
restore_original_scan_state = true;
leave_beam_off_at_end = true;

%% end of config

assert(exist('configure_grab_basename', 'file') == 2, ...
    'configure_grab_basename.m not found on path.');
assert(exist('grab_and_save_with_metadata', 'file') == 2, ...
    'grab_and_save_with_metadata.m not found on path.');

if exist('hWP', 'var') && ~isempty(hWP)
    hSI = hWP.hSI;
elseif evalin('base', "exist('hWP','var')")
    hWP = evalin('base', 'hWP');
    hSI = hWP.hSI;
elseif evalin('base', "exist('hSI','var')")
    hSI = evalin('base', 'hSI');
else
    error('Could not find hWP or hSI in workspace.');
end

assert(isvalid(hSI), 'hSI handle is invalid.');
assert(~isempty(hSI.hScan2D.hBeams), 'No beam handles found at hSI.hScan2D.hBeams.');
beam = hSI.hScan2D.hBeams{1};

prev = snapshotState(hSI, beam);
if restore_original_scan_state
    c = onCleanup(@()restoreState(hSI, beam, prev)); %#ok<NASGU>
end

try
    hSI.hRoiManager.scanType = 'frame';
catch
end

if apply_fov_shift
    applyFovShift(hSI, fov_shift_fast, fov_shift_slow, fov_shift_mode);
end

results = repmat(struct('z_um', nan, 'ablation', [], 'imaging', []), numel(zs), 1);

disp('starting...')
for zIdx = 1:numel(zs)
    z = zs(zIdx);
    fprintf('starting #%d at z=%.3f um\n', zIdx, z);

    hSI.hMotors.moveSampleNoQuery([NaN, NaN, z], true);
    pause(move_settle_s);

    % Ablation grab
    setBeamPowerFrac(beam, Pf_ablation);
    pdt_ablation_actual = applyFrameScanSettings( ...
        hSI, ablation_pixels_per_line, ablation_lines_per_frame, ablation_pixel_dwell_s);
    fprintf('  ablation: %d x %d, target PDT=%.3g s, actual PDT=%.3g s\n', ...
        ablation_pixels_per_line, ablation_lines_per_frame, ...
        ablation_pixel_dwell_s, pdt_ablation_actual);

    stemA = sprintf('%s_z%s_ablation', experiment_label, zToStem(z));
    cfgA = configure_grab_basename(save_dir, stemA, ...
        'HSI', hSI, ...
        'UserMetadata', struct( ...
            'experiment', experiment_label, ...
            'grab_type', 'ablation', ...
            'z_um', z, ...
            'pixels_per_line', ablation_pixels_per_line, ...
            'lines_per_frame', ablation_lines_per_frame, ...
            'pixel_dwell_target_s', ablation_pixel_dwell_s, ...
            'pixel_dwell_actual_s', pdt_ablation_actual, ...
            'beam_power_fraction', Pf_ablation, ...
            'scan_shift_fast', hSI.hRoiManager.scanAngleShiftFast, ...
            'scan_shift_slow', hSI.hRoiManager.scanAngleShiftSlow));
    outA = grab_and_save_with_metadata('HSI', hSI, 'Config', cfgA);

    pause(between_grabs_s);

    % Imaging grab
    setBeamPowerFrac(beam, Pf_imaging);
    pdt_imaging_actual = applyFrameScanSettings( ...
        hSI, imaging_pixels_per_line, imaging_lines_per_frame, imaging_pixel_dwell_s);
    fprintf('  imaging : %d x %d, target PDT=%.3g s, actual PDT=%.3g s\n', ...
        imaging_pixels_per_line, imaging_lines_per_frame, ...
        imaging_pixel_dwell_s, pdt_imaging_actual);

    stemI = sprintf('%s_z%s_imaging', experiment_label, zToStem(z));
    cfgI = configure_grab_basename(save_dir, stemI, ...
        'HSI', hSI, ...
        'UserMetadata', struct( ...
            'experiment', experiment_label, ...
            'grab_type', 'imaging', ...
            'z_um', z, ...
            'pixels_per_line', imaging_pixels_per_line, ...
            'lines_per_frame', imaging_lines_per_frame, ...
            'pixel_dwell_target_s', imaging_pixel_dwell_s, ...
            'pixel_dwell_actual_s', pdt_imaging_actual, ...
            'beam_power_fraction', Pf_imaging, ...
            'scan_shift_fast', hSI.hRoiManager.scanAngleShiftFast, ...
            'scan_shift_slow', hSI.hRoiManager.scanAngleShiftSlow));
    outI = grab_and_save_with_metadata('HSI', hSI, 'Config', cfgI);

    results(zIdx).z_um = z;
    results(zIdx).ablation = outA;
    results(zIdx).imaging = outI;

    pause(between_grabs_s);
end

if leave_beam_off_at_end && ~restore_original_scan_state
    setBeamPowerFrac(beam, 0);
end

assignin('base', 'ablation_imaging_results', results);
disp('done.')

function pdt_actual = applyFrameScanSettings(hSI, pixels_per_line, lines_per_frame, pdt_target_s)
    validateattributes(pixels_per_line, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(lines_per_frame, {'numeric'}, {'scalar', 'finite', 'positive'});
    validateattributes(pdt_target_s, {'numeric'}, {'scalar', 'finite', 'positive'});

    hSI.hRoiManager.pixelsPerLine = round(pixels_per_line);
    hSI.hRoiManager.linesPerFrame = round(lines_per_frame);

    hScan = hSI.hScan2D;
    applied = false;

    % Strategy 1: choose sampleRate/pixelBinFactor pair nearest to target dwell.
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
                    hScan.sampleRate = bestRate;
                catch
                end
                hScan.pixelBinFactor = bestBin;
                applied = true;
            end
        end
    catch
    end

    % Strategy 2 fallback: linePeriod = pdt * pixelsPerLine
    if ~applied
        try
            hSI.hRoiManager.linePeriod = pdt_target_s * double(hSI.hRoiManager.pixelsPerLine);
            applied = true;
        catch
        end
    end

    pdt_actual = double(hSI.hScan2D.scanPixelTimeMean);
    if ~applied
        warning('Could not set pixel dwell time on this scan mode/hardware. Using current timing.');
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

function s = snapshotState(hSI, beam)
    s = struct();
    s.scanType = '';
    s.pixelsPerLine = nan;
    s.linesPerFrame = nan;
    s.linePeriod = nan;
    s.sampleRate = nan;
    s.pixelBinFactor = nan;
    s.scanAngleShiftFast = nan;
    s.scanAngleShiftSlow = nan;
    s.beamPowerFraction = nan;

    try, s.scanType = hSI.hRoiManager.scanType; catch, end
    try, s.pixelsPerLine = double(hSI.hRoiManager.pixelsPerLine); catch, end
    try, s.linesPerFrame = double(hSI.hRoiManager.linesPerFrame); catch, end
    try, s.linePeriod = double(hSI.hRoiManager.linePeriod); catch, end
    try, s.sampleRate = double(hSI.hScan2D.sampleRate); catch, end
    try, s.pixelBinFactor = double(hSI.hScan2D.pixelBinFactor); catch, end
    try, s.scanAngleShiftFast = double(hSI.hRoiManager.scanAngleShiftFast); catch, end
    try, s.scanAngleShiftSlow = double(hSI.hRoiManager.scanAngleShiftSlow); catch, end
    try, s.beamPowerFraction = double(beam.powerFraction); catch, end
end

function restoreState(hSI, beam, s)
    try, hSI.hRoiManager.scanType = s.scanType; catch, end
    try, hSI.hRoiManager.pixelsPerLine = s.pixelsPerLine; catch, end
    try, hSI.hRoiManager.linesPerFrame = s.linesPerFrame; catch, end
    try, hSI.hRoiManager.linePeriod = s.linePeriod; catch, end
    try, hSI.hScan2D.sampleRate = s.sampleRate; catch, end
    try, hSI.hScan2D.pixelBinFactor = s.pixelBinFactor; catch, end
    try, hSI.hRoiManager.scanAngleShiftFast = s.scanAngleShiftFast; catch, end
    try, hSI.hRoiManager.scanAngleShiftSlow = s.scanAngleShiftSlow; catch, end
    try, setBeamPowerFrac(beam, s.beamPowerFraction); catch, end
end
