function setupZSliceSelectionUI(app)
%SETUPZSLICSELECTIONUI Add an optional, backward-compatible Z slice range.

% The controls are created at run time so older .mlapp files and scripts that
% construct a lightweight/mock app do not need new App Designer properties.

    if ~isprop(app, 'UIFigure') || isempty(app.UIFigure) || ...
            ~isvalid(app.UIFigure) || ~isprop(app, 'Arbitrary_Line_Scan_Grid')
        return;
    end

    if isappdata(app.UIFigure, 'WPZSliceSelectionUI')
        ui = getappdata(app.UIFigure, 'WPZSliceSelectionUI');
        if isstruct(ui) && isfield(ui, 'Panel') && isvalid(ui.Panel)
            return;
        end
    end

    app.Settings.ZSliceSelection = defaultSelection();

    parent = app.Arbitrary_Line_Scan_Grid;
    parent.RowHeight = {'1x', '1x', '1x', '1x', '1.35x'};
    try
        heights = app.Right_Grid.RowHeight;
        if numel(heights) >= 2
            heights{2} = '3x';
            app.Right_Grid.RowHeight = heights;
        end
    catch
        % Layout remains usable even when the enclosing grid is unavailable.
    end

    ui.Panel = uipanel(parent, 'Title', 'Z slices to execute');
    ui.Panel.Layout.Row = 5;
    ui.Panel.Layout.Column = [1 2];

    grid = uigridlayout(ui.Panel, [2 4]);
    grid.ColumnWidth = {'fit', '1x', 'fit', '1x'};
    grid.RowHeight = {'fit', 'fit'};
    grid.ColumnSpacing = 6;
    grid.RowSpacing = 1;
    grid.Padding = [5 1 5 2];

    ui.Enabled = uicheckbox(grid, 'Text', 'Limit');
    ui.Enabled.Layout.Row = 1;
    ui.Enabled.Layout.Column = 1;

    ui.First = uispinner(grid, 'Limits', [1 Inf], 'Step', 1, 'Value', 1);
    ui.First.Layout.Row = 1;
    ui.First.Layout.Column = 2;
    ui.First.Tooltip = 'First slice number, counting from the lowest Z value.';

    ui.ToLabel = uilabel(grid, 'Text', 'through');
    ui.ToLabel.Layout.Row = 1;
    ui.ToLabel.Layout.Column = 3;

    ui.Last = uispinner(grid, 'Limits', [1 Inf], 'Step', 1, 'Value', 1);
    ui.Last.Layout.Row = 1;
    ui.Last.Layout.Column = 4;
    ui.Last.Tooltip = 'Last slice number (inclusive), counting from the lowest Z value.';

    ui.Status = uilabel(grid, 'Text', 'All slices (low Z to high Z)');
    ui.Status.Layout.Row = 2;
    ui.Status.Layout.Column = [1 4];
    ui.Status.FontSize = 10;

    ui.Enabled.ValueChangedFcn = @(~,~) syncZSliceSelectionFromUI(app);
    ui.First.ValueChangedFcn = @(~,~) syncZSliceSelectionFromUI(app);
    ui.Last.ValueChangedFcn = @(~,~) syncZSliceSelectionFromUI(app);
    setappdata(app.UIFigure, 'WPZSliceSelectionUI', ui);
    refreshZSliceSelectionUI(app, false);
end

function s = defaultSelection()
    s = struct('Enabled', false, 'FirstIndex', 1, 'LastIndex', Inf);
end
