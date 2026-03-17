function z = getZaxis_fast(hSI_or_hSICtl, varargin)
%GETZAXIS_FAST Read current Z from ScanImage in sample or axes frame.
%
% z = getZaxis_fast(hSI_or_hSICtl, 'Frame', 'sample|axes', 'Query', false)

    p = inputParser;
    p.FunctionName = 'getZaxis_fast';
    addRequired(p, 'hSI_or_hSICtl');
    addParameter(p, 'Frame', 'sample', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Query', false, @(x) (islogical(x) && isscalar(x)) || ...
        (isnumeric(x) && isscalar(x) && any(x == [0, 1])));
    parse(p, hSI_or_hSICtl, varargin{:});

    frame = lower(validatestring(p.Results.Frame, {'sample', 'axes'}));
    doQuery = logical(p.Results.Query);
    [~, hMotors] = zaxis_fast_resolve(hSI_or_hSICtl);
    z = zaxis_fast_readPosition(hMotors, frame, doQuery);
end
