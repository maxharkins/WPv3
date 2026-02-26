classdef Path
    properties
        Coordinates
        FlowDirection
    end

    properties
        Plot
        PlotStyle = {'Color', 'k', 'LineStyle', 'none', 'Marker', '.'};
    end

    methods
        function [obj] = Replot(obj, app)
            if isempty(obj.Coordinates)
                return;
            end
            zeroV       = zeros(size(obj.Coordinates, 1), 1);
            obj.Plot    = plot3(app.Axes_XYZ,                       ...
                obj.Coordinates(:,1), obj.Coordinates(:,2), zeroV,  ...
                obj.PlotStyle{:});
        end
    end
end
