function handlePlanScanPaths(app)
% handlePlanScanPaths
% Gatekeeper for "Prep Galvo Paths" / "Plan ScanPaths" button.
% Verifies minimal prerequisites and runs scan-path preparation.

    % ---- Require imported/active geometry ----
    [hasTri, hasNodes] = hasGeometry(app);
    if ~(hasTri || hasNodes)
        issue(app, 'No geometry loaded. Import an STL or TXT file first.');
        return;
    end

    % ---- Ensure stack object exists ----
    if isempty(app.hStacks) || ~isvalid(app.hStacks)
        app.hStacks = Stacks(app, hasTri);
    end

    % ---- Run prep ----
    try
        app.hStacks = app.hStacks.getScanPaths(app);
    catch ME
        issue(app, sprintf('Prep failed.\n\nDetails: %s', ME.message));
        return;
    end

    % ---- Basic post-check ----
    if isempty(app.hStacks.ScanPaths)
        issue(app, 'Prep completed, but no scan paths were generated.');
        return;
    end

    refreshZSliceSelectionUI(app, false);

    disp('Prepped ScanPaths.');
    success(app, 'ScanPaths planning complete.');
end

function [hasTri, hasNodes] = hasGeometry(app)
hasTri = false;
hasNodes = false;

if isempty(app.hMask)
        return;
    end

    if isprop(app.hMask, 'hTri') && ~isempty(app.hMask.hTri)
        hasTri = ~isempty(app.hMask.hTri.BasePoints);
    end

    if isprop(app.hMask, 'hNodes') && ~isempty(app.hMask.hNodes)
        hasNodes = ~isempty(app.hMask.hNodes.BasePoints);
    end
end

function issue(app, msg)
try
    uialert(app.UIFigure, msg, 'Cannot Prep ScanPaths');
catch
    warning('%s', msg);
end
end

function success(app, msg)
try
    uialert(app.UIFigure, msg, 'Plan Complete', 'Icon', 'success');
catch
    disp(msg);
end
end
