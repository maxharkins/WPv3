function info = wpRememberImportedFile(app, filePath)
%WPREMEMBERIMPORTEDFILE Persist imported file metadata on the UI figure.
% Label format example: violin.STL -> violin_STL

    info = struct('path', '', 'label', 'imported_file');
    if nargin < 2 || isempty(filePath)
        return;
    end

    [~, stem, ext] = fileparts(filePath);
    ext = regexprep(ext, '^\.', '');
    if isempty(ext)
        rawLabel = stem;
    else
        rawLabel = sprintf('%s_%s', stem, ext);
    end
    safeLabel = wpSanitizeLabel(rawLabel);

    info.path = filePath;
    info.label = safeLabel;

    try
        setappdata(app.UIFigure, 'WPImportedFilePath', filePath);
        setappdata(app.UIFigure, 'WPImportedFileLabel', safeLabel);
    catch
        % No UI context available.
    end
end
