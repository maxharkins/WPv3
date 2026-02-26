classdef Nodes
    properties (Access = public)
        BasePoints          = []; % Coordinates in original frame
        TransformedPoints   = []; % Coordinates with applied transformations
        ArbitraryZs      = [];
    end

    properties (Access = public)
        PlotStyle           = {'Color', 'r', 'LineStyle', 'none', 'Marker', '.', 'MarkerSize', 0.1};
        Plot                = [];
    end
    
    methods (Access = public)

        function obj = Nodes(coordinates, position)
            % coords are 3D node coordinates.
            % position is [x y z]. 

            % Initialize empty properties explicitly
            obj.BasePoints = [];
            obj.TransformedPoints = [];
            obj.Plot = [];

            if nargin < 2 || isempty(coordinates) || isempty(position)
                return;
            end

            % Center coordinates at origin.
            obj.BasePoints = coordinates - (max(coordinates) + min(coordinates)) / 2;
            obj.TransformedPoints = obj.BasePoints + position; % Apply position
            obj.ArbitraryZs = sortrows(unique(obj.TransformedPoints(:,3)), 'descend');
        end

    end
    
end