function stagePath = getStagePath(~, geomPts, tileSpacing, type)
% getStagePath
% Computes XY stage tile centers from arbitrary geometry points.
%
% Inputs
%   geomPts     : Nx3 or Nx2 geometry points (nodes, STL vertices, etc.)
%   tileSpacing : [dx dy] or scalar
%   type        : 'ablation' (snap-to-geometry) or 'tile' (bounding grid)
%
% Output
%   stagePath   : Mx3 [x y z] unique tile centers, z = 0

    if nargin < 4 || isempty(type)
        type = 'ablation';
    end

    if isempty(geomPts)
        error('getStagePath:EmptyGeometry', ...
              'Geometry points are empty. Cannot compute stage path.');
    end

    % Ensure XY only
    xy = geomPts(:,1:2);

    % Normalize tile spacing
    if isscalar(tileSpacing)
        tileSpacing = [tileSpacing tileSpacing];
    end

    dx = tileSpacing(1);
    dy = tileSpacing(2);

    switch lower(type)

        % ==========================================================
        % Ablation mode: snap geometry to nearest tile centers
        % ==========================================================
        case 'ablation'

            xmin = min(xy(:,1));
            xmax = max(xy(:,1));
            ymin = min(xy(:,2));
            ymax = max(xy(:,2));
        
            Lx = xmax - xmin;
            Ly = ymax - ymin;
        
            % FOV size equals tile spacing + 2*overlap,
            % but here tileSpacing already represents center-to-center spacing.
            % We need actual FOV size:
            FOVx = dx;
            FOVy = dy;
        
            % If you have overlap, then dx = FOV - 2*overlap.
            % So recover FOV like this if needed:
            % FOVx = dx + 2*overlap;
            % FOVy = dy + 2*overlap;
        
            % ---- Number of tiles needed (CRITICAL FIX)
            if Lx <= FOVx
                Nx = 1;
            else
                Nx = ceil((Lx - FOVx)/dx) + 1;
            end
        
            if Ly <= FOVy
                Ny = 1;
            else
                Ny = ceil((Ly - FOVy)/dy) + 1;
            end
        
            % ---- Center tiles over geometry
            xCenter = (xmin + xmax)/2;
            yCenter = (ymin + ymax)/2;
        
            if Nx == 1
                xCenters = xCenter;
            else
                spanX = dx*(Nx-1);
                xCenters = linspace(xCenter - spanX/2, ...
                                    xCenter + spanX/2, Nx);
            end
        
            if Ny == 1
                yCenters = yCenter;
            else
                spanY = dy*(Ny-1);
                yCenters = linspace(yCenter - spanY/2, ...
                                    yCenter + spanY/2, Ny);
            end
        
            [xGrid, yGrid] = meshgrid(xCenters, yCenters);
        
            stagePath = [ ...
                xGrid(:), ...
                yGrid(:), ...
                zeros(numel(xGrid),1) ];
        
            stagePath = sortrows(stagePath, [1 2], 'ascend');

        % ==========================================================
        % Tile mode: full rectangular tiling of bounding box
        % ==========================================================
        case 'tile'

            xmin = min(xy(:,1));
            xmax = max(xy(:,1));
            ymin = min(xy(:,2));
            ymax = max(xy(:,2));

            % Expand bounds to full tile coverage
            xmin = floor(xmin/dx) * dx;
            xmax = ceil (xmax/dx) * dx;
            ymin = floor(ymin/dy) * dy;
            ymax = ceil (ymax/dy) * dy;

            [xGrid, yGrid] = meshgrid(xmin:dx:xmax, ymin:dy:ymax);

            stagePath = [ ...
                xGrid(:), ...
                yGrid(:), ...
                zeros(numel(xGrid),1) ];

            stagePath = sortrows(stagePath, [1 2], 'ascend');

        otherwise
            error('getStagePath:InvalidType', ...
                  'Unknown stage path type: %s', type);
    end
end