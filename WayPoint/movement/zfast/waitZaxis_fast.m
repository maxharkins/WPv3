function tWait_s = waitZaxis_fast(hSI_or_hSICtl, varargin)
%WAITZAXIS_FAST Wait until Z motor motion completes.
%
% tWait_s = waitZaxis_fast(hSI_or_hSICtl, 'PollInterval', 0.005, 'Timeout', 5)

    p = inputParser;
    p.FunctionName = 'waitZaxis_fast';
    addRequired(p, 'hSI_or_hSICtl');
    addParameter(p, 'PollInterval', 0.005, @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x > 0);
    addParameter(p, 'Timeout', 5, @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x > 0);
    parse(p, hSI_or_hSICtl, varargin{:});

    pollInterval = double(p.Results.PollInterval);
    timeout = double(p.Results.Timeout);
    [~, ~, hZMotor] = zaxis_fast_resolve(hSI_or_hSICtl);

    t0 = tic;
    while true
        tfMoving = zaxis_fast_queryMoving(hZMotor);
        if ~tfMoving
            break;
        end
        if toc(t0) > timeout
            error('waitZaxis_fast:Timeout', ...
                'Timed out waiting for Z move completion (%.3f s).', timeout);
        end
        pause(pollInterval);
    end
    tWait_s = toc(t0);
end
