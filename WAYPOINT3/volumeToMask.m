function maskData = volumeToMask(vol)
% volumeToMask
%   Convert Volume3D struct to Mask-compatible triangulation

    tri = triangulation(vol.faces, vol.xyz);

    maskData = struct( ...
        'Points',           tri.Points, ...
        'ConnectivityList', tri.ConnectivityList ...
    );
end
