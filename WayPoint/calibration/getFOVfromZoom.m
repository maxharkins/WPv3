function [x,y] = getFOVfromZoom(zoomFactor)
    x = 512 / (0.5850*zoomFactor - 0.1017);
    y = x;
end