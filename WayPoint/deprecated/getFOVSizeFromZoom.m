function [stageSize] = getFOVSizeFromZoom(zoomFactor)
    if ~isnumeric(zoomFactor)
        zoomFactor = zoomFactor.Zoom_Factor_Spinner.Value;
    end
    
    focalSize_um = 512/ (0.5850 * zoomFactor - 0.1017);
    stageSize = [focalSize_um, focalSize_um];    
end