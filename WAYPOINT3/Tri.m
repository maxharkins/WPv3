classdef Tri
    properties
        BasePoints          = []; % Original Points from STL
        TransformedPoints   = []; % Points updated by position
        ConnectivityList    = []; % Connectivity List
    end

    properties
        PatchStyle           = struct( ...
            'Color',        'r', ...
            'Opacity',      0.25 ...
            );
        Patch                = []; % Patch on graph
    end

    methods (Access = public)
        
        function obj = Tri(Triangulation, position)
            if nargin < 2 || isempty(position)
                position = [0 0 0];
            end
            if nargin < 1 || isempty(Triangulation)
                return;
            end

            obj.BasePoints          = Triangulation.Points; % mm to µm
            obj.TransformedPoints   = Triangulation.Points + position; % Convert and apply position
            obj.ConnectivityList    = Triangulation.ConnectivityList;
        end
        
    end
end