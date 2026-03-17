function PockelsCalibration = pockelsCellPowerCalibration(hSI, varargin)
%POCKELSCELLPOWERCALIBRATION Calibrate Pockels-cell power vs command fraction.
%   PockelsCalibration = pockelsCellPowerCalibration(hSI, ...)
%
% Required input:
%   hSI : ScanImage handle with
%         hSI.hScan2D.hBeams{1}.setPowerFraction(pf)
%
% Name-value options:
%   'MeasureFcn'       : function handle returning downstream power (W)
%                        Usage: powerW = MeasureFcn(pf, idx)
%                        If empty, user is prompted at each sample.
%   'PFSamples'        : command fractions in [0,1]
%                        Default: [0.00 0.15 0.30 0.45 0.60 0.75 0.90 1.00]
%   'SettleTime'       : pause time after setPowerFraction, seconds (default 1)
%   'SavePath'         : MAT file path (optional, auto-generated when empty)
%   'SaveDir'          : output folder (optional, auto-generated when empty)
%   'FigureDPI'        : exported figure resolution (default 400)
%   'ShowPlot'         : true/false (default true)
%   'RMSEThreshold'    : acceptance threshold in W (default 0.05)
%
% This workflow explicitly measures the transfer from power meter location
% immediately downstream of the Pockels cell to power exiting the objective.
%
% Output struct includes:
%   - Sinusoidal model for downstream (PC) power
%   - Derived model for objective-exit power
%   - Two-way conversion helpers between command percent and objective mW
%   - Artifact/log paths for lab recordkeeping

parser = inputParser;
parser.addRequired('hSI');
parser.addParameter('MeasureFcn', []);
parser.addParameter('PFSamples', [0.00 0.15 0.30 0.45 0.60 0.75 0.90 1.00], ...
    @(x) isnumeric(x) && isvector(x));
parser.addParameter('SettleTime', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.addParameter('SavePath', '', ...
    @(x) ischar(x) || isstring(x));
parser.addParameter('SaveDir', '', ...
    @(x) ischar(x) || isstring(x));
parser.addParameter('FigureDPI', 400, @(x) isnumeric(x) && isscalar(x) && x >= 150);
parser.addParameter('ShowPlot', true, @(x) islogical(x) && isscalar(x));
parser.addParameter('RMSEThreshold', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
parser.parse(hSI, varargin{:});
opts = parser.Results;

pf_samples = opts.PFSamples(:);
if any(pf_samples < 0 | pf_samples > 1)
    error('PFSamples must be within [0, 1].');
end

N = numel(pf_samples);
power_measured = zeros(N, 1);

% ----- Step 1: Measure transfer from downstream PC to objective exit -----
fprintf('\n%s\n', repmat('=', 1, 78));
fprintf('POCKELS CALIBRATION STEP 1/2: MEASURE OPTICAL PATH TRANSFER\n');
fprintf('%s\n', repmat('=', 1, 78));
fprintf(['Measure with the same meter and sensor:\n' ...
         '  1) Immediately downstream of the Pockels cell\n' ...
         '  2) Exiting the objective\n']);
fprintf(['Laser will be commanded to 100%% only when you confirm readiness,\n' ...
         'and turned back to 0%% immediately after each reading.\n' ...
         'These two values define the run-specific transfer factor.\n\n']);

% Force 100% command for transfer measurements.
pfTransfer = 1.0;

askReadyOrAbort('Ready to start calibrating? [y/N]: ');
setPowerFractionSafe(hSI, pfTransfer);
pause(opts.SettleTime);
powerDownstream_ref_W = promptPositiveScalar( ...
    'Enter power immediately downstream of the Pockels cell (W): ');
setPowerFractionSafe(hSI, pfTransfer);
pause(opts.SettleTime);
powerObjective_ref_W = promptPositiveScalar( ...
    'Enter power exiting the objective (W): ');
setPowerFractionSafe(hSI, 0.0);

powerEfficiency = powerDownstream_ref_W / powerObjective_ref_W;

fprintf('\nComputed transfer factor (downstream/objective) = %.6f x\n', powerEfficiency);
fprintf('Objective power ~= downstream power / %.6f\n', powerEfficiency);

fprintf('\n%s\n', repmat('-', 1, 78));
fprintf('POCKELS CALIBRATION STEP 2/2: DOWNSTREAM POWER VS COMMAND PERCENT\n');
fprintf('%s\n\n', repmat('-', 1, 78));

for i = 1:N
    pf = pf_samples(i);
    setPowerFractionSafe(hSI, pf);
    pause(opts.SettleTime);

    if isempty(opts.MeasureFcn)
        prompt = sprintf('Enter downstream power (W) for Power Fraction = %.2f%%: ', pf*100);
        measured_value = input(prompt);
    else
        measured_value = opts.MeasureFcn(pf, i);
    end

    if ~isnumeric(measured_value) || ~isscalar(measured_value) || ~isfinite(measured_value)
        error('Measured power must be a finite scalar numeric value (W).');
    end
    power_measured(i) = measured_value;
    setPowerFractionSafe(hSI, 0.0);
end

x = pf_samples * 100;
y = power_measured;
model = @(p, xData) p(1) .* sin(p(2) .* xData + p(3)).^2 + p(4);

A0 = max(y) - min(y);   % full amplitude
D0 = min(y);            % baseline (near 0)
omega0 = pi / 200;      % fine for now
phi0 = 0;

p0 = [A0 omega0 phi0 D0];

try
    fitOpts = optimoptions('lsqcurvefit', 'Display', 'off');
    
    lb = [0,          0,        -pi/8,   0];
    ub = [10*max(y),  pi/100,    pi/8,   max(y)];
    
    p = lsqcurvefit(model, p0, x, y, lb, ub, fitOpts);
catch
    % Fallback if Optimization Toolbox is unavailable.
    objective = @(pp) sum((model(pp, x) - y) .^ 2);
    p = fminsearch(objective, p0);
end

A = p(1);
omega = p(2);
phi = p(3);
D = p(4);

y_fit = model(p, x);
RMSE = sqrt(mean((y_fit - y) .^ 2));

Pmin = D - abs(A);
Pmax = D + abs(A);

PockelsCalibration = struct();
PockelsCalibration.A = A;
PockelsCalibration.omega = omega;
PockelsCalibration.phi = phi;
PockelsCalibration.D = D;
PockelsCalibration.powerEfficiency = powerEfficiency;
PockelsCalibration.Pmin = Pmin;
PockelsCalibration.Pmax = Pmax;
PockelsCalibration.pf_samples = pf_samples;
PockelsCalibration.power_measured = power_measured;
PockelsCalibration.RMSE = RMSE;
PockelsCalibration.RMSEThreshold = opts.RMSEThreshold;
PockelsCalibration.RMSEAccepted = RMSE < opts.RMSEThreshold;
PockelsCalibration.referenceMeasurement = struct( ...
    'downstreamPower_W', powerDownstream_ref_W, ...
    'objectivePower_W', powerObjective_ref_W);

% Downstream-PC model space (W)
PockelsCalibration.percentToPowerPC_W = @(percent) percentToPowerModel(percent, A, omega, phi, D);
PockelsCalibration.powerPC_WToPercent = @(powerPC_W) powerToPercentModel(powerPC_W, A, omega, phi, D);
% Objective model space (W, then mW helpers)
PockelsCalibration.percentToPowerObjective_W = @(percent) percentToPowerModel(percent, A, omega, phi, D) ./ powerEfficiency;
PockelsCalibration.powerObjective_WToPercent = @(powerObj_W) powerToPercentModel(powerObj_W .* powerEfficiency, A, omega, phi, D);
PockelsCalibration.percentToPowerObjective_mW = @(percent) 1e3 .* PockelsCalibration.percentToPowerObjective_W(percent);
PockelsCalibration.powerObjective_mWToPercent = @(powerObj_mW) PockelsCalibration.powerObjective_WToPercent(powerObj_mW ./ 1e3);
% Backward compatibility aliases
PockelsCalibration.percentToPower = PockelsCalibration.percentToPowerPC_W;
PockelsCalibration.powerToPercent = PockelsCalibration.powerPC_WToPercent;
PockelsCalibration.pcPowerToObjectivePower = @(powerPC_W) powerPC_W ./ powerEfficiency;
PockelsCalibration.objectivePowerToPCPower = @(powerObj_W) powerObj_W .* powerEfficiency;

PockelsCalibration.equations = struct( ...
    'downstream_W', 'P_pc_W = A*sin(omega*Pct + phi)^2 + D', ...
    'objective_W', 'P_obj_W = (A*sin(omega*Pct + phi) + D) / powerEfficiency', ...
    'objective_mW', 'P_obj_mW = 1000*(A*sin(omega*Pct + phi) + D)/powerEfficiency');

fig = [];
ax = [];
if opts.ShowPlot
    fig = figure('Name', 'Pockels Calibration', 'Color', 'w');
    ax = axes(fig);
    plot(ax, x, y, 'ko', 'MarkerFaceColor', [0.1 0.4 0.9], 'DisplayName', 'Measured downstream');
    hold on;
    xFine = linspace(0, 100, 500);
    yFine = model(p, xFine);
    plot(ax, xFine, yFine, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Fit downstream');
    yObjFine_mW = 1e3 .* (yFine ./ powerEfficiency);
    plot(ax, xFine, yObjFine_mW ./ 1e3, '--', 'Color', [0 0.5 0], 'LineWidth', 1.2, ...
        'DisplayName', 'Derived objective');
    xlabel(ax, 'Pockels Cell Command (%)');
    ylabel(ax, 'Power (W)');
    title(ax, sprintf('Pockels Cell Calibration (RMSE = %.4f W downstream)', RMSE));
    try
        subtitle(ax, sprintf('Transfer factor = %.5fx (downstream/objective)', powerEfficiency));
    catch
    end
    legend(ax, 'Location', 'best');
    grid on;
end

% ----- Save outputs (data + metadata + high-resolution figure) -----
[outDir, baseStem] = resolveOutputPath(opts.SavePath, opts.SaveDir);
if ~isfolder(outDir)
    mkdir(outDir);
end

savePath = fullfile(outDir, sprintf('%s.mat', baseStem));
metaPath = fullfile(outDir, sprintf('%s_metadata.txt', baseStem));
figPath = fullfile(outDir, sprintf('%s_plot.png', baseStem));

calibrationMeta = struct();
calibrationMeta.generatedAt_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
calibrationMeta.host = string(getenv('COMPUTERNAME'));
if strlength(calibrationMeta.host) == 0
    calibrationMeta.host = string(getenv('HOSTNAME'));
end
calibrationMeta.pf_samples = pf_samples;
calibrationMeta.downstreamPower_measured_W = power_measured;
calibrationMeta.transferMeasurement = struct( ...
    'downstream_W', powerDownstream_ref_W, ...
    'objective_W', powerObjective_ref_W, ...
    'powerEfficiency_downstream_over_objective', powerEfficiency);
calibrationMeta.fit = struct( ...
    'A', A, 'omega', omega, 'phi', phi, 'D', D, ...
    'RMSE_W_downstream', RMSE, ...
    'RMSEThreshold_W_downstream', opts.RMSEThreshold, ...
    'RMSEAccepted', RMSE < opts.RMSEThreshold);
calibrationMeta.paths = struct('mat', savePath, 'metadataTxt', metaPath, 'figurePng', figPath);

save(savePath, 'PockelsCalibration', 'calibrationMeta');
writeMetadataLog(metaPath, PockelsCalibration, calibrationMeta, opts);

if opts.ShowPlot && ~isempty(fig) && isgraphics(ax)
    try
        % Export only the main axes to avoid the "too much of figure" export issue.
        exportgraphics(ax, figPath, 'Resolution', opts.FigureDPI);
    catch
        % Fallback for older MATLAB variants.
        print(fig, figPath, '-dpng', sprintf('-r%d', round(opts.FigureDPI)));
    end
end

PockelsCalibration.paths = calibrationMeta.paths;
PockelsCalibration.generatedAt_local = calibrationMeta.generatedAt_local;
PockelsCalibration.calibrationMeta = calibrationMeta;

% Auto-register into active WP app when available.
try
    hWP = evalin('base', 'hWP');
    if ~isempty(hWP) && isvalid(hWP) && isprop(hWP, 'Settings')
        hWP.Settings.PockelsCalibration = PockelsCalibration;
        if isfield(hWP.Settings, 'Power_pct') && isnumeric(hWP.Settings.Power_pct) && isfinite(hWP.Settings.Power_pct)
            obj_mW = PockelsCalibration.percentToPowerObjective_mW(hWP.Settings.Power_pct);
            hWP.Settings.Power_mW = double(obj_mW);
            if isprop(hWP, 'Power_mW_Edit_Field')
                hWP.Power_mW_Edit_Field.Value = double(obj_mW);
            end
        end
    end
catch
end

fprintf('\nCalibration saved:\n');
fprintf('  MAT:      %s\n', savePath);
fprintf('  Metadata: %s\n', metaPath);
if opts.ShowPlot
    fprintf('  Figure:   %s\n', figPath);
end
end

function power = percentToPowerModel(percent, A, omega, phi, D)
power = A .* sin(omega .* percent + phi).^2 + D;
end

function percent = powerToPercentModel(power, A, omega, phi, D)
if abs(A) < eps
    error('Calibration amplitude is too small; inversion is ill-defined.');
end
if abs(omega) < eps
    error('Calibration omega is too small; inversion is ill-defined.');
end

Pmin = D;
Pmax = D + A;
tol = 1e-9;
if any(power < (Pmin - tol) | power > (Pmax + tol))
    error('Requested power outside calibrated range [%.6g, %.6g] W.', Pmin, Pmax);
end

power = power(:);
percent = zeros(size(power));
period = abs(pi / omega);

for i = 1:numel(power)
    s = (power(i) - D) / A;
    s = min(max(s, 0), 1);
    alpha = asin(sqrt(s));

    b1 = (alpha - phi) / omega;
    b2 = (pi - alpha - phi) / omega;

    nMin = floor((0 - max([b1 b2])) / period) - 1;
    nMax = ceil((100 - min([b1 b2])) / period) + 1;
    k = nMin:nMax;

    candidates = [b1 + k * period, b2 + k * period];
    inRange = candidates >= 0 & candidates <= 100;
    candidates = candidates(inRange);

    if isempty(candidates)
        wrapped = mod([b1 b2], period);
        candidates = wrapped;
        inRange = candidates >= 0 & candidates <= 100;
        candidates = candidates(inRange);
    end

    if isempty(candidates)
        error('No valid percent solution found in [0, 100] for requested power.');
    end

    modeled = percentToPowerModel(candidates, A, omega, phi, D);
    [~, idx] = min(abs(modeled - power(i)));
    percent(i) = candidates(idx);
end
end

function v = promptPositiveScalar(promptText)
while true
    v = input(promptText);
    if isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0
        return;
    end
    fprintf('Input must be a positive finite scalar.\n');
end
end

function askReadyOrAbort(promptText)
reply = lower(strtrim(input(promptText, 's')));
if isempty(reply) || ~(strcmp(reply, 'y') || strcmp(reply, 'yes'))
    error('Calibration aborted by user before enabling laser output.');
end
end

function setPowerFractionSafe(hSI, pf)
%hSI.hScan2D.hBeams{1}.setPowerFraction(pf);
end

function [outDir, baseStem] = resolveOutputPath(savePathOpt, saveDirOpt)
savePathOpt = string(savePathOpt);
saveDirOpt = string(saveDirOpt);

if strlength(strtrim(savePathOpt)) > 0
    [outDir, stem, ext] = fileparts(char(savePathOpt));
    if isempty(outDir)
        outDir = pwd;
    end
    if isempty(ext)
        baseStem = stem;
    elseif strcmpi(ext, '.mat')
        baseStem = stem;
    else
        baseStem = [stem '_' ext(2:end)];
    end
    return;
end

if strlength(strtrim(saveDirOpt)) > 0
    outDir = char(saveDirOpt);
else
    outDir = tryResolveCalibrationFolder();
end

baseStem = sprintf('pockels_calibration_%s', datestr(now, 'yyyymmdd_HHMMSS'));
end

function outDir = tryResolveCalibrationFolder()
outDir = fullfile(pwd, 'calibration');
try
    ctx = wpEnsureDailyExperimentFolder('Create', true, 'DateTime', datetime('now'));
    if isfield(ctx, 'subdirs') && isfield(ctx.subdirs, 'calibration')
        outDir = ctx.subdirs.calibration;
    end
catch
end
end

function writeMetadataLog(metaPath, c, meta, opts)
fid = fopen(metaPath, 'w');
if fid < 0
    warning('Could not write calibration metadata log: %s', metaPath);
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, 'WayPoint Pockels Calibration Report\n');
fprintf(fid, '===================================\n\n');
fprintf(fid, 'Generated: %s\n', meta.generatedAt_local);
fprintf(fid, 'Host: %s\n\n', char(meta.host));

fprintf(fid, 'Protocol Summary\n');
fprintf(fid, '----------------\n');
fprintf(fid, ['1) Measured power immediately downstream of the Pockels cell.\n' ...
              '2) Measured power exiting the objective.\n' ...
              '3) Computed transfer factor (downstream/objective).\n' ...
              '4) Measured downstream power across command fractions.\n' ...
              '5) Fit sinusoidal response model and validated RMSE.\n\n']);

fprintf(fid, 'Transfer Measurement\n');
fprintf(fid, '--------------------\n');
fprintf(fid, 'Downstream reference power (W): %.9f\n', c.referenceMeasurement.downstreamPower_W);
fprintf(fid, 'Objective reference power (W):  %.9f\n', c.referenceMeasurement.objectivePower_W);
fprintf(fid, 'Transfer factor (x):            %.9f\n\n', c.powerEfficiency);

fprintf(fid, 'Fit Parameters\n');
fprintf(fid, '--------------\n');
fprintf(fid, 'A: %.12g\n', c.A);
fprintf(fid, 'omega: %.12g\n', c.omega);
fprintf(fid, 'phi: %.12g\n', c.phi);
fprintf(fid, 'D: %.12g\n', c.D);
fprintf(fid, 'RMSE downstream (W): %.9f\n', c.RMSE);
fprintf(fid, 'RMSE threshold (W):  %.9f\n', opts.RMSEThreshold);
fprintf(fid, 'RMSE accepted:       %d\n\n', c.RMSEAccepted);

fprintf(fid, 'Model Equations\n');
fprintf(fid, '---------------\n');
fprintf(fid, 'Downstream model: %s\n', c.equations.downstream_W);
fprintf(fid, 'Objective model:  %s\n', c.equations.objective_W);
fprintf(fid, 'Objective mW:     %s\n\n', c.equations.objective_mW);

fprintf(fid, 'Sample Measurements (downstream, W)\n');
fprintf(fid, '-----------------------------------\n');
for i = 1:numel(c.pf_samples)
    fprintf(fid, 'Percent=%8.3f  Fraction=%7.4f  Power=%.9f\n', ...
        100*c.pf_samples(i), c.pf_samples(i), c.power_measured(i));
end

fprintf(fid, '\nOutput Artifacts\n');
fprintf(fid, '----------------\n');
fprintf(fid, 'MAT file:      %s\n', meta.paths.mat);
fprintf(fid, 'Metadata text: %s\n', meta.paths.metadataTxt);
fprintf(fid, 'Figure PNG:    %s\n', meta.paths.figurePng);
end
