function [x, y] = zoom2microns(zoomFactor)
    x = 512 ./ (0.5850 * zoomFactor - 0.1017);
    y = x;
end
