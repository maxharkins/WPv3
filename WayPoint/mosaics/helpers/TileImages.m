classdef TileImages
    properties
        Image       % img
        Size        % [l w h]
        Position    % [x y z]
        Range       % M_2x2
        Corners
        X
        Y
        Z
    end

    methods
        function [obj] = TileImages(varargin)
            parser = inputParser;

            addParameter(parser, 'Image', []);
            addParameter(parser, 'Size', []);
            addParameter(parser, 'Position', []);

            parse(parser, varargin{:})

            Image = parser.Results.Image;
            Size = parser.Results.Size;
            Position = parser.Results.Position;

            if    ~isempty(Image);    obj.Image =    Image; end
            if     ~isempty(Size);     obj.Size =     Size; end
            if ~isempty(Position); obj.Position = Position; end
            obj = obj.UpdateRange;
        end

        function [obj] = set.Image(obj,Image)
            obj.Image = Image;
            obj = obj.UpdateRange;
        end
        function [obj] = set.Size(obj,Size)
            obj.Size = Size;
            obj = obj.UpdateRange;
        end
        function [obj] = set.Position(obj,Position)
            obj.Position = Position;
            obj = obj.UpdateRange;
        end

        function [obj] = UpdateRange(obj)
            if isempty(obj.Image) || isempty(obj.Size) || isempty(obj.Position)
                return;
            end
            obj.Range(1,:) = [obj.Position(1), obj.Position(1) + obj.Size(1)];
            obj.Range(2,:) = [obj.Position(2), obj.Position(2) + obj.Size(2)];

            % Compute half sizes
            half_w = obj.Size(1) / 2;
            half_h = obj.Size(2) / 2;                
        
            % Define the four corners in 3D space
            obj.Corners = [ obj.Position(1) - half_w, obj.Position(2) - half_h, obj.Position(3);  % Bottom-left
                            obj.Position(1) + half_w, obj.Position(2) - half_h, obj.Position(3);  % Bottom-right
                            obj.Position(1) + half_w, obj.Position(2) + half_h, obj.Position(3);  % Top-right
                            obj.Position(1) - half_w, obj.Position(2) + half_h, obj.Position(3)]; % Top-left
        end
    end
end





            
            


