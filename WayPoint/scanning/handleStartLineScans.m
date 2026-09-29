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

    % Capture the latest controls and reject an empty range before any
    % hardware movement occurs.
    syncZSliceSelectionFromUI(app);
    if ~hasAnySelectedScanPaths(app)
        issue(app, 'The selected Z-slice range contains no playable scan paths. Adjust the slice range and try again.');
        return;
    end

    % ---- Start scan ----
    try
        startScanMapping(app);
    catch ME
        issue(app, sprintf('Scan failed.\n\nDetails: %s', ME.message));
        return;
    end

    if isprop(app, 'isCancelled') && app.isCancelled
        cancelled(app, 'Line scan sequence cancelled.');
        return;
    end

    success(app, 'Line scan sequence complete.');
end

function tf = hasAnySelectedScanPaths(app)
tf = false;
stack = app.hStacks;
for t = 1:numel(stack.ScanPaths)
    tile = stack.ScanPaths{t};
    if isempty(tile) || ~iscell(tile) || t > numel(stack.ArbitraryZs)
        continue;
    end
    if isrow(tile), tile = tile.'; end
    zs = stack.ArbitraryZs{t};
    zs = zs(:);
    n = min(numel(tile), numel(zs));
    tile = tile(1:n);
    zs = zs(1:n);
    selected = getSelectedZSliceIndices(app, zs);
    for k = selected(:).'
        if ~isempty(tile{k}) && size(tile{k},1) >= 2
            tf = true;
            return;
        end
    end
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

function cancelled(app, msg)
try
    uialert(app.UIFigure, msg, 'Scan Cancelled', 'Icon', 'info');
catch
    disp(msg);
end
end
