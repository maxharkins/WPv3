function data = parseTXTFile(filePath)
% parseTXTFile  Read TXT coordinate file
%
% Output fields:
%   data.raw     [N x D] double
%   data.bounds  [1 x 2D]

    raw = readmatrix(filePath);

    if isempty(raw) || ~isnumeric(raw)
        error('TXT file contains no numeric data.');
    end

    if size(raw,2) < 2
        error('TXT file must have at least 2 columns.');
    end

    bounds = [min(raw,[],1), max(raw,[],1)];

    data = struct( ...
        'raw',    raw, ...
        'bounds', bounds ...
    );
end
