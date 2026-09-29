function selection = syncZSliceSelectionFromUI(app)
%SYNCZSLICSELECTIONFROMUI Validate controls and copy them into Settings.

    selection = struct('Enabled', false, 'FirstIndex', 1, 'LastIndex', Inf);
    if isprop(app, 'Settings') && isstruct(app.Settings) && ...
            isfield(app.Settings, 'ZSliceSelection')
        selection = normalizeSelection(app.Settings.ZSliceSelection);
    end

    ui = [];
    try
        if isappdata(app.UIFigure, 'WPZSliceSelectionUI')
            ui = getappdata(app.UIFigure, 'WPZSliceSelectionUI');
        end
    catch
    end

    if isstruct(ui) && isfield(ui, 'Enabled') && isvalid(ui.Enabled)
        selection.Enabled = logical(ui.Enabled.Value);
        selection.FirstIndex = max(1, round(double(ui.First.Value)));
        selection.LastIndex = max(selection.FirstIndex, round(double(ui.Last.Value)));
        ui.First.Value = selection.FirstIndex;
        ui.Last.Value = selection.LastIndex;

        if selection.Enabled
            enabledState = 'on';
        else
            enabledState = 'off';
        end
        ui.First.Enable = enabledState;
        ui.Last.Enable = enabledState;
        ui.ToLabel.Enable = enabledState;
        maxSlices = ui.Last.Limits(2);
        if ~isfinite(maxSlices)
            maxSlices = selection.LastIndex;
        end
        if selection.Enabled
            ui.Status.Text = sprintf('Executing slices %d-%d of %d (low Z to high Z)', ...
                selection.FirstIndex, selection.LastIndex, maxSlices);
        elseif maxSlices > 1
            ui.Status.Text = sprintf('All %d slices (low Z to high Z)', maxSlices);
        elseif maxSlices == 1
            ui.Status.Text = 'All slices (1 currently available)';
        else
            ui.Status.Text = 'All slices (none loaded yet)';
        end
    end

    app.Settings.ZSliceSelection = selection;
end

function s = normalizeSelection(s)
    defaults = struct('Enabled', false, 'FirstIndex', 1, 'LastIndex', Inf);
    if ~isstruct(s), s = defaults; return; end
    names = fieldnames(defaults);
    for i = 1:numel(names)
        if ~isfield(s, names{i})
            s.(names{i}) = defaults.(names{i});
        end
    end
    s.Enabled = logical(s.Enabled);
    if ~isscalar(s.FirstIndex) || ~isfinite(s.FirstIndex), s.FirstIndex = 1; end
    if ~isscalar(s.LastIndex) || isnan(s.LastIndex), s.LastIndex = Inf; end
    s.FirstIndex = max(1, round(double(s.FirstIndex)));
    s.LastIndex = max(s.FirstIndex, round(double(s.LastIndex)));
end
