function rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um)
%WPRASTERSPACINGFROMBEAMWAIST Canonical raster spacing for Gaussian beams.
%   Raster spacing is fixed to half the beam waist diameter.

    if ~(isnumeric(beamWaistDiameter_um) && isscalar(beamWaistDiameter_um) ...
            && isfinite(beamWaistDiameter_um) && beamWaistDiameter_um > 0)
        error('BeamWaistDiameter_um must be a finite scalar > 0.');
    end

    rasterSpacing_um = double(beamWaistDiameter_um) / 2;
end
