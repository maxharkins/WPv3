function refreshZSliceSelectionUI(app, resetSelection)
%REFRESHZSLICSELECTIONUI Update selector bounds after import or path prep.

    if nargin < 2
        resetSelection = false;
    end
    if ~isprop(app, 'UIFigure') || isempty(app.UIFigure) || ...
            ~isvalid(app.UIFigure) || ~isappdata(app.UIFigure, 'WPZSliceSelectionUI')
        return;
    end

    ui = getappdata(app.UIFigure, 'WPZSliceSelectionUI');
    if ~isstruct(ui) || ~isfield(ui, 'Panel') || ~isvalid(ui.Panel)
        return;
    end

    maxSlices = availableSliceCount(app);
    displayMax = max(1, maxSlices);

    if resetSelection
        ui.Enabled.Value = false;
        firstValue = 1;
        lastValue = displayMax;
    else
        firstValue = min(max(1, round(ui.First.Value)), displayMax);
        lastValue = min(max(firstValue, round(ui.Last.Value)), displayMax);
        if ~ui.Enabled.Value
            firstValue = 1;
            lastValue = displayMax;
        end
    end

    % Temporarily relax bounds so shrinking an imported stack cannot make
    % assignment fail because an old spinner value is now out of range.
    ui.First.Limits = [1 Inf];
    ui.Last.Limits = [1 Inf];
    ui.First.Value = firstValue;
    ui.Last.Value = lastValue;
    ui.First.Limits = [1 displayMax];
    ui.Last.Limits = [1 displayMax];

    syncZSliceSelectionFromUI(app);
end

function n = availableSliceCount(app)
    n = 0;
    try
        stack = app.hStacks;
        if ~isempty(stack) && isvalid(stack) && ~isempty(stack.ScanPaths)
            for t = 1:numel(stack.ScanPaths)
                n = max(n, numel(stack.ScanPaths{t}));
            end
        elseif ~isempty(stack) && isvalid(stack) && ~isempty(stack.MeshEdgeLayers)
            n = numel(stack.MeshEdgeLayers);
        end
    catch
        n = 0;
    end
end
