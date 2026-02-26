function tf = isScanPathTXT(filePath)
% isScanPathTXT  Detect if TXT file is a scan-path export

    fid = fopen(filePath,'r');
    if fid == -1
        error('Cannot open file for reading.');
    end
    c = onCleanup(@() fclose(fid));

    maxLines = 30;
    tf = false;

    for i = 1:maxLines
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end

        s = strtrim(line);
        if isempty(s)
            continue;
        end

        if startsWith(s,'NumTiles:') || ...
           startsWith(s,'--- Tile') || ...
           startsWith(s,'NumZs:') || ...
           startsWith(s,'Z-Index:') || ...
           startsWith(s,'Z-Level:')
            tf = true;
            return;
        end
    end
end
