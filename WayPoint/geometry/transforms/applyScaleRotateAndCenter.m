function data = applyScaleRotateAndCenter(data)
% applyScaleRotateAndCenter
%   - Assumes imported coordinates are in microns
%   - Allows user to correct scale if source units were wrong
%   - Optionally applies discrete 3D orientation
%   - Centers geometry at origin

    % ------------------------------------------------------------
    % Select coordinate field
    % ------------------------------------------------------------
    if isfield(data, 'xyz')
        coords = data.xyz;
        coordField = 'xyz';
        label = 'STL geometry';
    elseif isfield(data, 'raw')
        coords = data.raw;
        coordField = 'raw';
        label = 'Coordinate geometry';

        assert(size(coords,2) == 3, ...
            'applyScaleRotateAndCenter expects Nx3 coordinate data.');
    else
        error('Data struct has no coordinate field.');
    end

    % ------------------------------------------------------------
    % Compute size
    % ------------------------------------------------------------
    mins = min(coords,[],1);
    maxs = max(coords,[],1);
    spans = maxs - mins;
    longest = max(spans);

    % ------------------------------------------------------------
    % User dialog
    % ------------------------------------------------------------
    prompt = {
        sprintf([ ...
            '%s detected.\n\n' ...
            'Current longest dimension: %.3f microns (as imported).\n\n' ...
            'If this is incorrect, enter the REAL longest dimension (microns).'], ...
            label, longest), ...
        'Optional: uniform scale factor (advanced):'
    };

    answer = inputdlg(prompt, 'Confirm Scale', [1 60; 1 60]);

    if isempty(answer)
        error('Import cancelled by user.');
    end

    targetLen   = str2double(answer{1});
    manualScale = str2double(answer{2});

    % ------------------------------------------------------------
    % Determine scale
    % ------------------------------------------------------------
    if ~isnan(targetLen) && targetLen > 0
        scale = targetLen / longest;
    elseif ~isnan(manualScale) && manualScale > 0
        scale = manualScale;
    else
        scale = 1;
    end

    if ~isfinite(scale) || scale <= 0
        error('Invalid scale factor.');
    end

    if size(coords,2) == 3 && size(coords,1) >= 3
        if isfield(data, "faces")
            faces = data.faces;
        else
            faces = [];
        end
        [coordsRot, didApply] = rotate3DGui(coords, 'Title', ['Rotate: ' label], 'Faces', faces, 'UseScatter', false);
        if didApply
            coords = coordsRot;
        end
    end

    % ------------------------------------------------------------
    % Apply scaling and centering
    % ------------------------------------------------------------
    coords = coords * scale;
    ctr = (max(coords,[],1) + min(coords,[],1)) / 2;
    coords = coords - ctr;

    % ------------------------------------------------------------
    % Write back
    % ------------------------------------------------------------
    data.(coordField) = coords;
    data.bounds = [min(coords,[],1), max(coords,[],1)];
end
