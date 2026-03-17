function [x, y] = microns2zoom(fovMicronsX, fovMicronsY)
    if nargin < 2 || isempty(fovMicronsY)
        fovMicronsY = fovMicronsX;
    end

    x = (512 ./ fovMicronsX + 0.1017) / 0.5850;
    y = (512 ./ fovMicronsY + 0.1017) / 0.5850;
end
