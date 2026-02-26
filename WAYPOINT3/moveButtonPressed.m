function moveButtonPressed(app, object, direction, magnitude)
    % object is 'stage', 'nodes', or 'cassette' (cassette not set up yet).
    % direction is 'left', 'right', 'forward', 'backward', 'up', 'down'.
    % magnitude is a positive scalar (microns).

    switch direction
        case 'right';       unitVector = [ 1  0  0];
        case 'left';        unitVector = [-1  0  0];
        case 'forward';     unitVector = [ 0  1  0];
        case 'backward';    unitVector = [ 0 -1  0];
        case 'up';          unitVector = [ 0  0 -1];
        case 'down';        unitVector = [ 0  0  1];
    end

    relativeDest = magnitude * unitVector;
    
    if strcmpi(object, 'mask')
        globalDest = app.hMask.Position + relativeDest;
    elseif strcmpi(object, 'stage')
        globalDest = app.hStage.Position + relativeDest;
    end
        
    movementRequest(app, object, globalDest);

end
