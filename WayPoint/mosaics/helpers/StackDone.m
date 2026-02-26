function StackDone(app, eventData)
    WellIdx = eventData.WellIdx;
    app.PathIdx = app.PathIdx + 1;
    if strcmp(app.ImagingType, 'ablation')
        pathObj = 'aPath';
    elseif strcmp(app.ImagingType, 'tiling')
        pathObj = 'iPath';
    end

    if app.PathIdx > size(app.hWells(WellIdx).(pathObj).Coordinates, 1)
        return;
    end
    goToStagePath(app, app.ImagingType, WellIdx, app.PathIdx)
end