function [defaultFullPath, defaultDir, baseLabel] = wpBuildScanPathExportDefault(app, suggestedName)
%WPBUILDSCANPATHEXPORTDEFAULT Resolve default path/name for ScanPaths exports.

    if nargin < 2 || isempty(suggestedName)
        suggestedName = 'ScanPaths.txt';
    end

    baseLabel = 'imported_file';
    try
        if isprop(app, 'UIFigure') && isappdata(app.UIFigure, 'WPImportedFileLabel')
            baseLabel = getappdata(app.UIFigure, 'WPImportedFileLabel');
        end
    catch
    end
    baseLabel = wpSanitizeLabel(baseLabel);

    [~, ~, ext] = fileparts(suggestedName);
    if isempty(ext)
        ext = '.txt';
    end

    ctx = [];
    try
        ctx = wpEnsureDailyExperimentFolder('Create', true);
        defaultDir = ctx.subdirs.processed;
    catch
        defaultDir = pwd;
    end

    timestamp = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
    defaultName = sprintf('%s_ScanPaths_%s%s', baseLabel, timestamp, ext);
    defaultFullPath = fullfile(defaultDir, defaultName);
end
