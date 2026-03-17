function wpSyncPowerFields(app, sourceField)
%WPSYNCPOWERFIELDS Keep Power % and objective-exit mW fields synchronized.
% sourceField: 'pct' or 'mw'

if nargin < 2
    error('wpSyncPowerFields requires app and sourceField.');
end

if ~isprop(app, 'UIFigure') || isempty(app.UIFigure) || ~isvalid(app.UIFigure)
    return;
end

busyKey = 'WPPowerSyncBusy';
if isappdata(app.UIFigure, busyKey) && getappdata(app.UIFigure, busyKey)
    return;
end
setappdata(app.UIFigure, busyKey, true);
cleanupObj = onCleanup(@() setappdata(app.UIFigure, busyKey, false)); %#ok<NASGU>

if ~isprop(app, 'Settings') || ~isstruct(app.Settings)
    app.Settings = struct();
end

src = lower(string(sourceField));
switch src
    case "pct"
        if ~isprop(app, 'Power_Pct_Edit_Field')
            return;
        end
        pct = double(app.Power_Pct_Edit_Field.Value);
        pct = max(0, min(100, pct));
        app.Power_Pct_Edit_Field.Value = pct;
        app.Settings.Power_pct = pct;

        cal = getCalibration(app);
        if ~isempty(cal)
            mW = pctToObjective_mW(cal, pct);
            if isfinite(mW)
                app.Settings.Power_mW = mW;
                if isprop(app, 'Power_mW_Edit_Field')
                    app.Power_mW_Edit_Field.Value = mW;
                end
            end
        end

    case "mw"
        if ~isprop(app, 'Power_mW_Edit_Field')
            return;
        end
        mW = double(app.Power_mW_Edit_Field.Value);
        app.Settings.Power_mW = mW;

        cal = getCalibration(app);
        if isempty(cal)
            warnNoCalibration(app);
            return;
        end

        pct = objective_mWToPct(cal, mW);
        pct = max(0, min(100, pct));
        app.Settings.Power_pct = pct;
        if isprop(app, 'Power_Pct_Edit_Field')
            app.Power_Pct_Edit_Field.Value = pct;
        end

    otherwise
        error('Unknown sourceField "%s". Use ''pct'' or ''mw''.', sourceField);
end
end

function cal = getCalibration(app)
cal = [];
try
    if isfield(app.Settings, 'PockelsCalibration') && isstruct(app.Settings.PockelsCalibration)
        c = app.Settings.PockelsCalibration;
        if ~isempty(fieldnames(c))
            cal = c;
        end
    end
catch
end
end

function mW = pctToObjective_mW(cal, pct)
mW = NaN;
try
    if isfield(cal, 'percentToPowerObjective_mW') && isa(cal.percentToPowerObjective_mW, 'function_handle')
        mW = double(cal.percentToPowerObjective_mW(pct));
        return;
    end
    if isfield(cal, 'A') && isfield(cal, 'omega') && isfield(cal, 'phi') && isfield(cal, 'D') && isfield(cal, 'powerEfficiency')
        powerW = cal.A .* sin(cal.omega .* pct + cal.phi) + cal.D;
        mW = double((powerW ./ cal.powerEfficiency) * 1e3);
    end
catch
    mW = NaN;
end
end

function pct = objective_mWToPct(cal, mW)
objW = mW / 1e3;
if isfield(cal, 'powerObjective_WToPercent') && isa(cal.powerObjective_WToPercent, 'function_handle')
    pct = double(cal.powerObjective_WToPercent(objW));
    return;
end
if isfield(cal, 'objectivePowerToPCPower') && isa(cal.objectivePowerToPCPower, 'function_handle') && ...
   isfield(cal, 'powerToPercent') && isa(cal.powerToPercent, 'function_handle')
    pcW = cal.objectivePowerToPCPower(objW);
    pct = double(cal.powerToPercent(pcW));
    return;
end

req = {'A','omega','phi','D','powerEfficiency'};
for i = 1:numel(req)
    if ~isfield(cal, req{i})
        error('PockelsCalibration is missing "%s".', req{i});
    end
end
pcW = objW * cal.powerEfficiency;
pct = invertPcPowerToPct(pcW, cal.A, cal.omega, cal.phi, cal.D);
end

function pct = invertPcPowerToPct(power, A, omega, phi, D)
if abs(A) < eps || abs(omega) < eps
    error('Calibration inversion is ill-defined.');
end

Pmin = D - abs(A);
Pmax = D + abs(A);
if power < Pmin - 1e-9 || power > Pmax + 1e-9
    error('Requested power is outside calibrated range.');
end

s = (power - D) / A;
s = min(max(s, -1), 1);
alpha = asin(s);

b1 = (alpha - phi) / omega;
b2 = (pi - alpha - phi) / omega;
period = abs(2*pi/omega);

nMin = floor((0 - max([b1 b2])) / period) - 1;
nMax = ceil((100 - min([b1 b2])) / period) + 1;
k = nMin:nMax;

candidates = [b1 + k*period, b2 + k*period];
candidates = candidates(candidates >= 0 & candidates <= 100);
if isempty(candidates)
    error('No valid percent found in [0,100] for requested power.');
end

modeled = A .* sin(omega .* candidates + phi) + D;
[~, idx] = min(abs(modeled - power));
pct = double(candidates(idx));
end

function warnNoCalibration(app)
msg = 'Power (mW) to percent conversion needs a Pockels calibration. Click Calibrate first.';
try
    uialert(app.UIFigure, msg, 'Missing Calibration', 'Icon', 'warning');
catch
    warning(msg);
end
end
