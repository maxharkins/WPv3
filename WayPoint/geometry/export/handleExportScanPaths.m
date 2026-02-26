function handleExportScanPaths(app)
% handleExportScanPaths
% Gatekeeper for exporting planned ScanPaths.
% Verifies readiness, prompts for destination, then exports.

    % ---- Ensure stack exists ----
    if ~isprop(app, 'hStacks') || isempty(app.hStacks)
        issue(app, 'No active stack found. Import and prep before exporting.');
        return;
    end

    % ---- Ensure scan paths exist ----
    if ~hasAnyScanPaths(app.hStacks)
        issue(app, 'No prepared ScanPaths found. Click "Plan ScanPaths" first.');
        return;
    end

    % ---- Re-evaluate effective dimensionality ----
    if ismethod(app.hStacks, 'queryIsEffectively2D')
        try
            app.hStacks.isEffectively2D = app.hStacks.queryIsEffectively2D();
        catch ME
            issue(app, sprintf('Could not determine 2D/3D stack state.\n\nDetails: %s', ME.message));
            return;
        end
    end

    % ---- Build suggested filename from spacing settings ----
    xyQuantStep_um = app.Settings.QuantFactorXY_um;

    if app.hStacks.isEffectively2D
        zStep_um = app.Extrusion_Z_Step_Size_Edit_Field.Value;
    else
        zStep_um = app.Settings.QuantFactorZ_um;
    end

    xyStr = strrep(sprintf('%.4g', xyQuantStep_um), '.', 'p');
    zStr  = strrep(sprintf('%.4g', zStep_um),  '.', 'p');
    suggestedName = sprintf('ScanPaths_Z-interval-%sum_XY-interval-%sum.txt', zStr, xyStr);

    % ---- Prompt destination ----
    [fileName, folderPath] = uiputfile( ...
        {'*.txt', 'Text Files (*.txt)'}, ...
        'Export ScanPaths', ...
        suggestedName);

    if isequal(fileName, 0) || isequal(folderPath, 0)
        return;
    end

    % ---- Export ----
    outPath = fullfile(folderPath, fileName);
    try
        app.hStacks.exportScanPaths(outPath);
    catch ME
        issue(app, sprintf('Export failed.\n\nDetails: %s', ME.message));
        return;
    end

    try
        uialert(app.UIFigure, sprintf('ScanPaths export complete.\n%s', outPath), ...
            'Export Complete', 'Icon', 'success');
    catch
        fprintf('ScanPaths export complete: %s\n', outPath);
    end
end

function tf = hasAnyScanPaths(stack)
tf = false;

if isempty(stack) || ~isvalid(stack) || isempty(stack.ScanPaths)
    return;
end

for t = 1:numel(stack.ScanPaths)
    tile = stack.ScanPaths{t};
    if isempty(tile)
        continue;
    end
    if ~iscell(tile)
        tf = true;
        return;
    end
    for z = 1:numel(tile)
        if ~isempty(tile{z}) && size(tile{z},1) >= 2
            tf = true;
            return;
        end
    end
end
end

function issue(app, msg)
try
    uialert(app.UIFigure, msg, 'Cannot Export ScanPaths');
catch
    warning('%s', msg);
end
end
