function refreshPlot(hWP)
    cla(hWP.Axes_XYZ);
    hold(hWP.Axes_XYZ, 'on');
    
    hWP.hStage = hWP.hStage.UpdateStagePlot(hWP);

    if isa(hWP.hMask, 'Mask')
        hWP.hMask = hWP.hMask.UpdateGeometry();
        hWP.hMask = hWP.hMask.PlotGeometry(hWP);
    end

    hWP.aPath.Plot = hWP.aPath.Replot(hWP);
    %hWP.iPath.Plot = hWP.iPath.Replot(hWP);

end

function plotPath(obj, wellIdx)
    coords = obj.aPath.Coordinates;
    if ~isempty(coords)
        obj.aPath.Plot = plot3(obj.Axes_XYZ, ...
            coords(:,1), coords(:,2), coords(:,3), ...
            '.', 'Color', 'k', 'LineWidth', .5 ...
        );
    end
end

