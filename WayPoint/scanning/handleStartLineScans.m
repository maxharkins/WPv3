function handleStartLineScans(app)
% handleStartLineScans
% Gatekeeper for "Start Line Scans" button.
% Verifies scan readiness and starts scanning.
% Does NOT run prep automatically; "Prep Galvo Paths" is the only prep path.

    % ---- Basic hardware guardrails ----
    if ~isprop(app, 'hSI') || isempty(app.hSI)
        issue(app, 'ScanImage handle is missing. Start ScanImage first.');
        return;
    end

    if ~isprop(app, 'hSICtl') || isempty(app.hSICtl)
        issue(app, 'ScanImage control handle is missing. Reinitialize app/ScanImage.');
        return;
    end

    % ---- Stack/geometry presence ----
    if isempty(app.hStacks) || ~isvalid(app.hStacks)
        issue(app, 'No active stack found. Import a file before starting scans.');
        return;
    end

    % ---- Ensure scan paths exist ----
    if ~hasAnyScanPaths(app.hStacks)
        issue(app, 'Scan paths are not prepared. Click "Prep Galvo Paths" first.');
        return;
    end

    % ---- Ensure stage path exists ----
    if isempty(app.aPath) || isempty(app.aPath.Coordinates)
        issue(app, 'Stage path is empty. Use "Prep Galvo Paths" before starting scans.');
        return;
    end

    % ---- Structural consistency checks ----
    scanPaths = app.hStacks.ScanPaths;
    if isempty(scanPaths)
        issue(app, 'Scan paths are empty. Use "Prep Galvo Paths" before starting scans.');
        return;
    end

    if ~isprop(app.hStacks, 'ArbitraryZs') || isempty(app.hStacks.ArbitraryZs)
        issue(app, 'Z-layer data is missing. Re-run "Prep Galvo Paths".');
        return;
    end

    if numel(app.hStacks.ArbitraryZs) < numel(scanPaths)
        issue(app, 'Mismatch between tile scan paths and Z-layers. Re-run "Prep Galvo Paths".');
        return;
    end

    % ---- Start scan ----
    try
        startScanMapping(app);
    catch ME
        issue(app, sprintf('Scan failed.\n\nDetails: %s', ME.message));
        return;
    end

    success(app, 'Line scan sequence complete.');
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
    uialert(app.UIFigure, msg, 'Cannot Start Scan');
catch
    warning('%s', msg);
end
end

function success(app, msg)
try
    uialert(app.UIFigure, msg, 'Scan Complete', 'Icon', 'success');
catch
    disp(msg);
end
end
