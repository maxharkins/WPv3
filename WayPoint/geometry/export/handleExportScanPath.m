function handleExportScanPath(app)
% handleExportScanPath
% Export planned ScanPaths to a text file.
%
% Flow:
%   1) Verify scan paths exist (requires "Plan ScanPaths" first).
%   2) Recompute whether the current plan is effectively 2D.
%   3) Build a descriptive default filename using XY/Z intervals.
%   4) Ask user for destination and call Stacks.exportScanPaths(...).

    % Guard: nothing to export until paths have been generated.
    if isempty(app.hStacks) || ~isvalid(app.hStacks) || isempty(app.hStacks.ScanPaths)
        warning("Please click 'Plan ScanPaths' before attempting export.");
        return;
    end

    % Re-evaluate the 2D/3D state from ArbitraryZs so naming reflects
    % the current stack contents (including any extrusion).
    if ismethod(app.hStacks, 'queryIsEffectively2D')
        app.hStacks.isEffectively2D = app.hStacks.queryIsEffectively2D();
    end

    % XY quantization step comes from scan quantization settings.
    xyQuantStep_um = app.Settings.QuantFactorXY_um;

    % Z spacing source depends on dimensionality:
    % - effectively 2D: use extrusion step size
    % - true 3D: use configured Z quantization
    if app.hStacks.isEffectively2D
        zStep_um = app.Extrusion_Z_Step_Size_Edit_Field.Value;
    else
        zStep_um = app.Settings.QuantFactorZ_um;
    end

    % Make a filesystem-friendly name (replace '.' with 'p').
    xyStr = strrep(sprintf('%.4g', xyQuantStep_um), '.', 'p');
    zStr  = strrep(sprintf('%.4g', zStep_um),  '.', 'p');
    suggestedName = sprintf('ScanPaths_Z-interval-%sum_XY-interval-%sum.txt', zStr, xyStr);

    % Prompt user for save path; no-op on cancel.
    [fileName, folderPath] = uiputfile( ...
        {'*.txt', 'Text Files (*.txt)'}, ...
        'Export ScanPaths', ...
        suggestedName);

    if isequal(fileName, 0) || isequal(folderPath, 0)
        return;
    end

    % Export using the canonical Stacks serializer.
    outPath = fullfile(folderPath, fileName);
    app.hStacks.exportScanPaths(outPath);

    % Confirm success in UI; fallback to console if alert fails.
    try
        uialert(app.UIFigure, sprintf('ScanPaths export complete.\n%s', outPath), 'Export Complete');
    catch
        fprintf('ScanPaths export complete: %s\n', outPath);
    end
end
