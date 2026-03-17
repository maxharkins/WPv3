function handleCalibratePockelCellButton(app)
%HANDLECALIBRATEPOCKELLCELLBUTTON Run Pockels calibration from the app button.

if nargin < 1 || isempty(app) || ~isvalid(app)
    error('A valid app handle is required.');
end
if ~isprop(app, 'hSI') || isempty(app.hSI)
    %error('ScanImage handle (app.hSI) is not available.');
end

fprintf('\n[WP] Starting Pockels calibration workflow...\n');
userChoice = "recalibrate";

[recentCal, recentPath, recentAgeMin] = tryLoadRecentCalibration();
if ~isempty(recentCal)
    userChoice = askCalibrationChoice(app, recentPath, recentAgeMin);
    switch userChoice
        case "reuse"
            cal = recentCal;
            fprintf('[WP] Reusing recent calibration: %s\n', recentPath);
        case "recalibrate"
            cal = pockelsCellPowerCalibration(app.hSI, 'ShowPlot', true);
        otherwise
            fprintf('[WP] Calibration cancelled by user.\n');
            return;
    end
else
    cal = pockelsCellPowerCalibration(app.hSI, 'ShowPlot', true);
end

app.Settings.PockelsCalibration = cal;
if ~isempty(recentPath) && strcmpi(userChoice, "reuse")
    app.Settings.PockelsCalibrationPath = recentPath;
elseif isfield(cal, 'paths') && isfield(cal.paths, 'mat')
    app.Settings.PockelsCalibrationPath = cal.paths.mat;
end

if isprop(app, 'Power_Pct_Edit_Field')
    app.Settings.Power_pct = app.Power_Pct_Edit_Field.Value;
end

if isfield(app.Settings, 'Power_pct') && isnumeric(app.Settings.Power_pct) && isfinite(app.Settings.Power_pct)
    try
        obj_mW = cal.percentToPowerObjective_mW(app.Settings.Power_pct);
        app.Settings.Power_mW = double(obj_mW);
        if isprop(app, 'Power_mW_Edit_Field')
            app.Power_mW_Edit_Field.Value = double(obj_mW);
        end
    catch
    end
end

fprintf('[WP] Pockels calibration complete.\n');
end

function choice = askCalibrationChoice(app, recentPath, recentAgeMin)
msg = sprintf(['A recent Pockels calibration was found.\n\n' ...
               'File: %s\nAge: %.1f minutes\n\n' ...
               'Reuse recent calibration or run a new calibration?'], recentPath, recentAgeMin);
choice = "recalibrate";
try
    btn = uiconfirm(app.UIFigure, msg, 'Pockels Calibration', ...
        'Options', {'Reuse Recent', 'Recalibrate', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3);
    switch string(btn)
        case "Reuse Recent"
            choice = "reuse";
        case "Recalibrate"
            choice = "recalibrate";
        otherwise
            choice = "cancel";
    end
catch
    % Fallback for environments without uiconfirm.
    fprintf('%s\n', msg);
    ansStr = lower(strtrim(input('Type [r]euse, [n]ew, or [c]ancel: ', 's')));
    if startsWith(ansStr, 'r')
        choice = "reuse";
    elseif startsWith(ansStr, 'c')
        choice = "cancel";
    else
        choice = "recalibrate";
    end
end
end

function [cal, matPath, ageMin] = tryLoadRecentCalibration()
cal = [];
matPath = '';
ageMin = NaN;

searchDirs = {};
try
    ctx = wpEnsureDailyExperimentFolder('Create', true, 'DateTime', datetime('now'));
    if isfield(ctx, 'subdirs') && isfield(ctx.subdirs, 'calibration')
        searchDirs{end+1} = ctx.subdirs.calibration; %#ok<AGROW>
    end
catch
end
searchDirs{end+1} = fullfile(pwd, 'calibration');

bestDnum = -Inf;
bestPath = '';
for i = 1:numel(searchDirs)
    d = searchDirs{i};
    if ~isfolder(d), continue; end
    files = dir(fullfile(d, '*calibration*.mat'));
    for k = 1:numel(files)
        if files(k).datenum > bestDnum
            bestDnum = files(k).datenum;
            bestPath = fullfile(files(k).folder, files(k).name);
        end
    end
end

if isempty(bestPath)
    return;
end

S = load(bestPath, 'PockelsCalibration');
if ~isfield(S, 'PockelsCalibration')
    return;
end

cal = S.PockelsCalibration;
matPath = bestPath;
ageMin = minutes(datetime('now') - datetime(bestDnum, 'ConvertFrom', 'datenum'));
end
