function movementRequest(app, object, globalDest)
    % object is 'stage', 'nodes', or 'cassette' (cassette not set up yet).
    % globalDest is [x y z].
    if strcmp(object, 'stage')
        prevDest = app.hStage.Position;
        relativeDest = globalDest - prevDest;
        resolvedDest = moveStage(app, globalDest, relativeDest);
        app.hStage.Position = resolvedDest;
    elseif strcmp(object, 'mask')
        app.hMask.Position = globalDest;
        app.hMask = app.hMask.UpdateGeometry;
    end

    refreshPlot(app);
end 
