function [micronsPerDegree] = getMicronsPerDegree(zoomFactor)
    defaultRoiSize = 20.0998;
    fillFractionSpatial = 0.9000;
    FOVmicrons = getFOVfromZoom(zoomFactor);

    FOVdegrees = defaultRoiSize ./ zoomFactor .* fillFractionSpatial;

    micronsPerDegree = FOVmicrons/FOVdegrees;
end

