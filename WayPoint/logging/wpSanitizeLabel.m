function out = wpSanitizeLabel(in)
%WPSANITIZELABEL Convert arbitrary text into a filename-safe token.

    if nargin < 1 || isempty(in)
        out = 'unnamed';
        return;
    end

    out = char(string(in));
    out = regexprep(out, '[^A-Za-z0-9]+', '_');
    out = regexprep(out, '_{2,}', '_');
    out = regexprep(out, '^_+', '');
    out = regexprep(out, '_+$', '');

    if isempty(out)
        out = 'unnamed';
    end
end
