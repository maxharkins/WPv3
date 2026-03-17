function out = moveZaxis_fast(hSI_or_hSICtl, zValue, varargin)
%MOVEZAXIS_FAST Fast Z-only motion API using existing ScanImage handles.
%
% out = moveZaxis_fast(hSI_or_hSICtl, zValue, ...
%     'Type', 'relative|absolute', ...
%     'Frame', 'sample|axes', ...
%     'QueryBefore', false, ...
%     'QueryAfter', false, ...
%     'Blocking', true, ...
%     'PollInterval', 0.005, ...
%     'Timeout', 5)

    p = inputParser;
    p.FunctionName = 'moveZaxis_fast';
    addRequired(p, 'hSI_or_hSICtl');
    addRequired(p, 'zValue', @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x));
    addParameter(p, 'Type', 'relative', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Frame', 'sample', @(s) ischar(s) || isstring(s));
    addParameter(p, 'QueryBefore', false, @isBoolLike);
    addParameter(p, 'QueryAfter', false, @isBoolLike);
    addParameter(p, 'Blocking', true, @isBoolLike);
    addParameter(p, 'PollInterval', 0.005, @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x > 0);
    addParameter(p, 'Timeout', 5, @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x) && x > 0);
    parse(p, hSI_or_hSICtl, zValue, varargin{:});

    type = lower(validatestring(p.Results.Type, {'relative', 'absolute'}));
    frame = lower(validatestring(p.Results.Frame, {'sample', 'axes'}));
    queryBefore = logical(p.Results.QueryBefore);
    queryAfter = logical(p.Results.QueryAfter);
    blocking = logical(p.Results.Blocking);
    pollInterval = double(p.Results.PollInterval);
    timeout = double(p.Results.Timeout);

    [~, hMotors, hZMotor, zAxis] = zaxis_fast_resolve(hSI_or_hSICtl);

    if zaxis_fast_queryMoving(hZMotor)
        error('moveZaxis_fast:MoveInProgress', ...
            'Z move already in progress. Wait for completion before issuing a new move.');
    end

    % Fast no-op path: if wrapper stage Z already equals requested sample-frame
    % target, skip hardware position reads and move command entirely.
    [cachedStageZ, hasCachedStageZ] = tryGetCachedStageZ(hSI_or_hSICtl);
    if hasCachedStageZ && strcmp(frame, 'sample') && ~queryBefore && ~queryAfter
        if strcmp(type, 'absolute')
            zTargetFast = double(zValue);
        else
            zTargetFast = cachedStageZ + double(zValue);
        end
        if abs(zTargetFast - cachedStageZ) <= 1e-9
            out = struct( ...
                'zBefore', cachedStageZ, ...
                'zTarget', zTargetFast, ...
                'zAfter', cachedStageZ, ...
                'deltaRequested', zTargetFast - cachedStageZ, ...
                'deltaActual', 0, ...
                'type', type, ...
                'frame', frame, ...
                'blocking', blocking, ...
                'queryBefore', queryBefore, ...
                'queryAfter', queryAfter, ...
                'pollInterval_s', pollInterval, ...
                'timeout_s', timeout, ...
                'tMove_s', 0);
            return;
        end
    end

    zBefore = zaxis_fast_readPosition(hMotors, frame, queryBefore);
    if strcmp(type, 'relative')
        zTarget = zBefore + double(zValue);
    else
        zTarget = double(zValue);
    end

    tMoveStart = tic;
    switch frame
        case 'sample'
            hMotors.moveSampleZ(zTarget, true);

        case 'axes'
            if ~isprop(hZMotor, 'numAxes')
                error('moveZaxis_fast:InvalidZMotor', ...
                    'Z motor does not expose numAxes required for axes-frame moves.');
            end
            numAxes = double(hZMotor.numAxes);
            if ~isscalar(numAxes) || ~isfinite(numAxes) || numAxes < 1 || mod(numAxes, 1) ~= 0
                error('moveZaxis_fast:InvalidZMotor', 'Invalid hZMotor.numAxes value.');
            end
            if zAxis > numAxes
                error('moveZaxis_fast:InvalidZAxisMapping', ...
                    'motorAxisXYZ(3) exceeds hZMotor.numAxes.');
            end
            tgt = nan(1, numAxes);
            tgt(zAxis) = zTarget;
            hZMotor.moveAsync(tgt);
    end

    if blocking
        t0 = tic;
        while true
            tfMoving = zaxis_fast_queryMoving(hZMotor);
            if ~tfMoving
                break;
            end
            if toc(t0) > timeout
                error('moveZaxis_fast:Timeout', ...
                    'Timed out waiting for Z move completion (%.3f s).', timeout);
            end
            pause(pollInterval);
        end
    end

    tMove = toc(tMoveStart);
    if blocking || queryAfter
        zAfter = zaxis_fast_readPosition(hMotors, frame, queryAfter);
        deltaActual = zAfter - zBefore;
    else
        zAfter = NaN;
        deltaActual = NaN;
    end

    out = struct( ...
        'zBefore', zBefore, ...
        'zTarget', zTarget, ...
        'zAfter', zAfter, ...
        'deltaRequested', zTarget - zBefore, ...
        'deltaActual', deltaActual, ...
        'type', type, ...
        'frame', frame, ...
        'blocking', blocking, ...
        'queryBefore', queryBefore, ...
        'queryAfter', queryAfter, ...
        'pollInterval_s', pollInterval, ...
        'timeout_s', timeout, ...
        'tMove_s', tMove);
end

function tf = isBoolLike(x)
tf = (islogical(x) && isscalar(x)) || ...
    (isnumeric(x) && isscalar(x) && any(x == [0, 1]));
end

function [z, tf] = tryGetCachedStageZ(inputHandle)
z = NaN;
tf = false;
try
    if isstruct(inputHandle)
        if ~isfield(inputHandle, 'hStage') || ~isfield(inputHandle.hStage, 'Position')
            return;
        end
        pos = inputHandle.hStage.Position;
    else
        if ~isprop(inputHandle, 'hStage') || isempty(inputHandle.hStage)
            return;
        end
        pos = inputHandle.hStage.Position;
    end
    if isnumeric(pos) && numel(pos) >= 3 && isfinite(pos(3))
        z = double(pos(3));
        tf = true;
    end
catch
    tf = false;
end
end
