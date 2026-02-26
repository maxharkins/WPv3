function vol = parseSTLFile(filePath)
% parseSTLFile  Read STL and return a normalized Volume3D struct
%
% Output fields:
%   vol.xyz      [N x 3] double
%   vol.faces    [M x 3] int
%   vol.bounds   [1 x 6] [xmin ymin zmin xmax ymax zmax]

    tri = stlread(filePath);

    xyz = double(tri.Points);
    faces = tri.ConnectivityList;

    bounds = [ ...
        min(xyz(:,1)), min(xyz(:,2)), min(xyz(:,3)), ...
        max(xyz(:,1)), max(xyz(:,2)), max(xyz(:,3)) ];

    vol = struct( ...
        'xyz',    xyz, ...
        'faces',  faces, ...
        'bounds', bounds ...
    );
end
