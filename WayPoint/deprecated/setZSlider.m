function setZSlider(app)
    obj = app.Z_Slider;
    WellIdx = app.WellIdx;

    numZslices = numel(app.hWells(WellIdx).hMask.hNodes.ArbitraryZs);
    obj.Limits = [0 numZslices+1];
end