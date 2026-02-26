classdef Mask
    properties
        hTri        % Tri class instance holding triangulation and geometry
        hNodes      % Nodes class instance
        Position    % Offset for the mask
        CopyOfWell  % Well index of original mask, if copied from another well
    end
    
    methods (Access = public)
       
        function obj = Mask(MaskData, Position, varargin)
        
            obj.hTri       = Tri;
            obj.hNodes     = Nodes;
            obj.CopyOfWell = 0;
        
            if nargin == 0
                obj.Position = [0 0 0];
                return;
            end
        
            % ---- positional arguments ----
            if nargin >= 1
                maskDataLocal = MaskData;
            else
                maskDataLocal = [];
            end
        
            if nargin >= 2
                obj.Position = Position;
            else
                obj.Position = [0 0 0];
            end
        
            % ---- optional name-value pairs ----
            if ~isempty(varargin)
                parser = inputParser;
                parser.addParameter('CopyOfWell', 0, @isnumeric);
                parser.parse(varargin{:});
                obj.CopyOfWell = parser.Results.CopyOfWell;
            end
        
            % ---- construct geometry ----
            if isstruct(maskDataLocal) && isfield(maskDataLocal, 'ConnectivityList')
                obj.hTri = Tri(maskDataLocal, obj.Position);
            elseif isnumeric(maskDataLocal) && size(maskDataLocal,2) == 3
                obj.hNodes = Nodes(maskDataLocal, obj.Position);
            end
        
            obj = obj.UpdateGeometry;
        end

        function obj = UpdateGeometry(obj)
            % Update geometry for hTri
            if ~isempty(obj.hTri.BasePoints)
                obj.hTri.TransformedPoints = obj.hTri.BasePoints + obj.Position;
            end

            % Update geometry for hNodes
            if ~isempty(obj.hNodes.BasePoints)
                obj.hNodes.TransformedPoints = obj.hNodes.BasePoints + obj.Position;
                obj.hNodes.ArbitraryZs = sortrows(unique(obj.hNodes.TransformedPoints(:,3)), 'descend');
            end
        end

        function obj = PlotGeometry(obj, app)
            % Plot nodes
            %if app.Show_Mask_Nodes_Button.Value 
                if ~isempty(obj.hNodes.BasePoints)
                    nodes = obj.hNodes.TransformedPoints;
                    obj.hNodes.Plot = plot3(app.Axes_XYZ, nodes(:,1), nodes(:,2), nodes(:,3), obj.hNodes.PlotStyle{:});
                end
            %end
            
            % % Plot triangulation
            if ~isempty(app.hStacks) && app.hStacks.isMeshScan
                obj.hTri.Patch = patch(app.Axes_XYZ, ...
                    'Vertices',     obj.hTri.TransformedPoints, ...
                    'Faces',        obj.hTri.ConnectivityList, ...
                    'FaceColor',    obj.hTri.PatchStyle.Color, ... 
                    'EdgeColor',    'none', ... 
                    'FaceAlpha',    obj.hTri.PatchStyle.Opacity ...
                    );
            end
        end
    end
end
