classdef Stage
    properties
        Size
        Position
    end
    
    properties
        Rectangle
        PlotStyle = {'Color', 'g', 'LineWidth', 4};
        Plot
    end

    methods
        function [obj] = Stage(app, Position)
            if nargin < 1
                return;
            elseif nargin < 2
                Position = [0 0 0];
            end
            obj.Position    = Position;
            obj.Size        = app.Settings.FOVSize_um;
            obj             = obj.UpdateStagePlot(app);
        end

        function [obj] = UpdateStagePlot(obj, app)
            if isempty(obj.Position) || isempty(obj.Size)
                return;
            end
            obj.Size        = [app.Settings.FOVSize_um, app.Settings.FOVSize_um];
            
            halfSize = obj.Size / 2;
            obj.Rectangle = [obj.Position(1:2) - halfSize, obj.Size(1:2)];

            xCorners = obj.Position(1) + [halfSize(1), -halfSize(1), -halfSize(1), halfSize(1), halfSize(1)];
            yCorners = obj.Position(2) + [halfSize(2), halfSize(2), -halfSize(2), -halfSize(2), halfSize(2)];
            zCorners = obj.Position(3) + zeros(1, 5);

            obj.Plot = plot3(app.Axes_XYZ, xCorners, yCorners, zCorners, obj.PlotStyle{:});
            
            stageLocation_str = sprintf('(%.2f, %.2f, %.2f)', obj.Position(1), obj.Position(2), obj.Position(3));
            app.Stage_Position_Edit_Field.Value = stageLocation_str;
        end

    end
end
    