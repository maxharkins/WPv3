classdef Nodes

    properties (Access = public)
        XYZ_mask    = [];
        XYZ         = [];
        Position    = [];
        Plot        = [];
    end
    
    methods (Access = public)

        function [obj] = Nodes(coordinates, position)
            % coords are 3D node coordinates.
            % position is [x y z]. 

            if nargin < 2 || isempty(coordinates) || isempty(position)
                return;
            end

            % Center coords at origin.
            obj.XYZ_mask = coordinates - (max(coordinates) + min(coordinates)) / 2;
            % Store position.
            obj.Position = position;
            % Store updated coordinates.
            obj.XYZ = obj.XYZ_mask + obj.Position;
        end

        function [obj] = update(obj)

            if isempty(obj.XYZ_mask) || isempty(obj.Position)
                return;
            end

            obj.XYZ = obj.XYZ_mask + obj.Position;

        end

    end
    
end



