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
userChoice = askCalibrationChoice(app, recentPath, recentAgeMin, ~isempty(recentCal));
switch userChoice
    case "import"
        [cal, selectedPath, ~, ok] = chooseCalibrationForReuse(app, recentPath, recentAgeMin);
        if ~ok
            fprintf('[WP] Calibration selection cancelled by user.\n');
            return;
        end
        recentPath = selectedPath;
        fprintf('[WP] Importing selected calibration: %s\n', recentPath);
    case "recalibrate"
        cal = pockelsCellPowerCalibration(app.hSI, 'ShowPlot', true);
    otherwise
        fprintf('[WP] Calibration cancelled by user.\n');
        return;
end

if ~isSinSquaredCalibration(cal)
    error(['Loaded calibration is not sin^2-compatible. ' ...
           'Run a fresh calibration with the updated sin^2 model.']);
end

app.Settings.PockelsCalibration = cal;
if ~isempty(recentPath) && strcmpi(userChoice, "import")
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

function choice = askCalibrationChoice(app, recentPath, recentAgeMin, hasRecent)
if nargin < 4
    hasRecent = false;
end

if hasRecent
    msg = sprintf(['A recent sin^2 Pockels calibration was found.\n\n' ...
                   'File: %s\nAge: %.1f minutes\n\n' ...
                   'Import a calibration file, or run a new calibration?'], recentPath, recentAgeMin);
else
    msg = ['No recent sin^2 Pockels calibration was found.' newline newline ...
           'Import a calibration file, or run a new calibration?'];
end
choice = "recalibrate";
try
    btn = uiconfirm(app.UIFigure, msg, 'Pockels Calibration', ...
        'Options', {'Import Calibration', 'Recalibrate', 'Cancel'}, ...
        'DefaultOption', 2, 'CancelOption', 3);
    switch string(btn)
        case "Import Calibration"
            choice = "import";
        case "Recalibrate"
            choice = "recalibrate";
        otherwise
            choice = "cancel";
    end
catch
    % Fallback for environments without uiconfirm.
    fprintf('%s\n', msg);
    ansStr = lower(strtrim(input('Type [i]mport, [n]ew, or [c]ancel: ', 's')));
    if startsWith(ansStr, 'i')
        choice = "import";
    elseif startsWith(ansStr, 'c')
        choice = "cancel";
    else
        choice = "recalibrate";
    end
end
end

function [cal, matPath, ageMin, ok] = chooseCalibrationForReuse(app, defaultPath, defaultAgeMin)
cal = [];
matPath = '';
ageMin = NaN;
ok = false;

[startDir, startFile] = fileparts(defaultPath);
if isempty(startDir) || ~isfolder(startDir)
    startDir = fullfile(pwd, 'calibration');
end
if isempty(startFile)
    startFile = '*.mat';
else
    startFile = [startFile '.mat'];
end

while true
    selectedPath = '';
    try
        [f, p] = uigetfile({'*.mat', 'MAT-files (*.mat)'}, ...
            'Select Pockels calibration file', fullfile(startDir, startFile));
        if isequal(f, 0) || isequal(p, 0)
            return;
        end
        selectedPath = fullfile(p, f);
    catch
        typed = strtrim(input('Enter full path to calibration .mat file (blank cancels): ', 's'));
        if isempty(typed)
            return;
        end
        selectedPath = typed;
    end

    try
        cal = loadCalibrationFromPath(selectedPath);
        break;
    catch ME
        warnMsg = sprintf('Selected file is not a valid sin^2 calibration:\n%s\n\n%s', selectedPath, ME.message);
        try
            uialert(app.UIFigure, warnMsg, 'Invalid Calibration File');
        catch
            fprintf('[WP] %s\n', warnMsg);
        end
    end
end

matPath = selectedPath;
try
    d = dir(matPath);
    ageMin = minutes(datetime('now') - datetime(d.datenum, 'ConvertFrom', 'datenum'));
catch
    ageMin = defaultAgeMin;
end
ok = true;
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

try
    cal = loadCalibrationFromPath(bestPath);
catch ME
    fprintf('[WP] Ignoring invalid recent calibration (%s): %s\n', bestPath, ME.message);
    cal = [];
    return;
end

matPath = bestPath;
ageMin = minutes(datetime('now') - datetime(bestDnum, 'ConvertFrom', 'datenum'));
end

function cal = loadCalibrationFromPath(matPath)
if ~isfile(matPath)
    error('File does not exist.');
end

S = load(matPath, 'PockelsCalibration');
if ~isfield(S, 'PockelsCalibration')
    error('MAT file is missing "PockelsCalibration".');
end

cal = S.PockelsCalibration;
if ~isSinSquaredCalibration(cal)
    error('Calibration model is not sin^2-compatible.');
end
end

function tf = isSinSquaredCalibration(cal)
tf = false;
if ~isstruct(cal)
    return;
end

if isfield(cal, 'modelType')
    modelType = lower(strtrim(char(string(cal.modelType))));
    if strcmp(modelType, 'sin2') || strcmp(modelType, 'sin^2')
        tf = true;
        return;
    end
end

if isfield(cal, 'equations') && isstruct(cal.equations) && isfield(cal.equations, 'downstream_W')
    eqDownstream = lower(strtrim(char(string(cal.equations.downstream_W))));
    tf = contains(eqDownstream, 'sin(') && contains(eqDownstream, '^2');
end
end
