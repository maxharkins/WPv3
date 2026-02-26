function data = confirmAndNormalizeSize(data)
% confirmAndNormalizeSize
%   - Assumes imported coordinates are in microns
%   - Allows user to correct scale if source units were wrong
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

        % make sure its nx3
        assert(size(coords,2) == 3, ...
            'confirmAndNormalizeSize expects Nx3 coordinate data.');
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
            'If this is incorrect, enter the REAL longest dimension in microns.'], ...
            label, longest), ...
        'Correct longest dimension (microns):', ...
        'Optional: uniform scale factor (advanced):'
    };

    answer = inputdlg(prompt, 'Confirm Size', [4 60; 1 60; 1 60]);

    if isempty(answer)
        error('Import cancelled by user.');
    end

    targetLen   = str2double(answer{2});
    manualScale = str2double(answer{3});

    % ------------------------------------------------------------
    % Determine scale
    % ------------------------------------------------------------
    if ~isnan(targetLen) && targetLen > 0
        scale = targetLen / longest;
    elseif ~isnan(manualScale) && manualScale > 0
        scale = manualScale;
    else
        scale = 1;   % accept imported scale as-is
    end

    if ~isfinite(scale) || scale <= 0
        error('Invalid scale factor.');
    end

    if size(coords,2) == 3 && size(coords,1) >= 3
        if isfield(data,"faces") % plot surf instead
            faces = data.faces;
        else
            faces = [];
        end
        [coordsRot, didApply] = rotate3DGui(coords, 'Title', ['Rotate: ' label], 'Faces',faces, 'UseScatter',false);
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
