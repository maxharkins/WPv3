function resolvedDest = moveStage(hWP, globalDest, relativeDest)
    % globalDest is [x y z].
    resolvedDest = globalDest;

    if ~isnumeric(globalDest) || numel(globalDest) < 3
        error('moveStage:InvalidDestination', 'globalDest must be a numeric [x y z] vector.');
    end
    if ~isnumeric(relativeDest) || numel(relativeDest) < 3
        error('moveStage:InvalidDelta', 'relativeDest must be a numeric [dx dy dz] vector.');
    end

    numSteps = round(relativeDest(1:2)/2.5);
    
    X = numSteps(1);
    Y = numSteps(2);

    message = sprintf('x%.1f, y%.1f\n', -X,Y);

    doXY = any(numSteps ~= 0);
    if doXY
        if isprop(hWP, 'serialPort') && isfield(hWP.serialPort, 'COM') && ~isempty(hWP.serialPort.COM)
            writeline(hWP.serialPort.COM, message);
        else
            warning('moveStage:NoSerialPort', 'Stage XY move requested but serial port COM handle is unavailable.');
        end
    end
    return % skip z...
    doZ = abs(relativeDest(3)) > 1e-9;
    if doZ
        out = moveZaxis_fast(hWP, globalDest(3), ...
            'Type', 'absolute', ...
            'Frame', 'sample', ...
            'QueryBefore', false, ...
            'QueryAfter', true, ...
            'Blocking', true, ...
            'PollInterval', 0.005, ...
            'Timeout', 5);

        if isfield(out, 'zAfter') && isfinite(out.zAfter)
            resolvedDest(3) = out.zAfter;
        else
            resolvedDest(3) = out.zTarget;
        end
    end

end
