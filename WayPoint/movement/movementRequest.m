function movementRequest(app, object, globalDest)
    % object is 'stage', 'nodes', or 'cassette' (cassette not set up yet).
    % globalDest is [x y z].
    if strcmp(object, 'stage')
        relativeDest = globalDest - app.hStage.Position;
        app.hStage.Position = globalDest;
        moveStage(app, globalDest, relativeDest);
    elseif strcmp(object, 'mask')
        app.hMask.Position = globalDest;
        app.hMask = app.hMask.UpdateGeometry;
    end

    refreshPlot(app);
end 