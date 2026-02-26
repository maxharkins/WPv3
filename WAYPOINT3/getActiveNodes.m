function [activeNodes] = getActiveNodes(nodes, slicePlane, sliceVal)

    if isempty(nodes)
        return;
    end

    switch upper(slicePlane)
        case 'XY'; slicePlane = [1 2]; sliceAxis = 3;
        case 'YZ'; slicePlane = [2 3]; sliceAxis = 1;
        case 'ZX'; slicePlane = [3 1]; sliceAxis = 2;
    end


    condition = nodes(:,sliceAxis) == sliceVal;
    if any(condition == 1)
        activeNodes = nodes(condition, slicePlane);
    else
        activeNodes = [];
    end

end