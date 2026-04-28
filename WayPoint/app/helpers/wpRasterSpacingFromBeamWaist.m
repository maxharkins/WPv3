function rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um, overlapFraction)
%WPRASTERSPACINGFROMBEAMWAIST Canonical raster spacing for Gaussian beams.
%   Raster spacing is beam waist diameter scaled by desired overlap:
%       spacing = beamWaistDiameter * (1 - overlapFraction)
%   overlapFraction defaults to 0.5 for backward compatibility.

    if ~(isnumeric(beamWaistDiameter_um) && isscalar(beamWaistDiameter_um) ...
            && isfinite(beamWaistDiameter_um) && beamWaistDiameter_um > 0)
        error('BeamWaistDiameter_um must be a finite scalar > 0.');
    end

    if nargin < 2 || isempty(overlapFraction)
        overlapFraction = 0.5;
    end
    if ~(isnumeric(overlapFraction) && isscalar(overlapFraction) ...
            && isfinite(overlapFraction) && overlapFraction >= 0 && overlapFraction < 1)
        error('overlapFraction must be a finite scalar in [0, 1).');
    end

    rasterSpacing_um = double(beamWaistDiameter_um) * (1 - double(overlapFraction));
end
