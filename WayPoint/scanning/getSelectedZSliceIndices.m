function [indices, info] = getSelectedZSliceIndices(hWP, zLevels)
%GETSELECTEDZSLICINDICES Resolve the inclusive low-Z-to-high-Z slice range.
% The returned indices address the original zLevels vector. Missing settings
% intentionally mean "all" for compatibility with scripts and older apps.

    zLevels = zLevels(:);
    n = numel(zLevels);
    selection = struct('Enabled', false, 'FirstIndex', 1, 'LastIndex', Inf);
    try
        if isstruct(hWP.Settings) && isfield(hWP.Settings, 'ZSliceSelection')
            candidate = hWP.Settings.ZSliceSelection;
            if isstruct(candidate)
                if isfield(candidate, 'Enabled'), selection.Enabled = logical(candidate.Enabled); end
                if isfield(candidate, 'FirstIndex'), selection.FirstIndex = candidate.FirstIndex; end
                if isfield(candidate, 'LastIndex'), selection.LastIndex = candidate.LastIndex; end
            end
        end
    catch
    end

    if n == 0
        indices = zeros(0,1);
        info = struct('Enabled', selection.Enabled, 'FirstIndex', 1, ...
            'LastIndex', 0, 'AvailableCount', 0, 'SelectedCount', 0);
        return;
    end

    firstIdx = sanitizeBound(selection.FirstIndex, 1);
    lastIdx = sanitizeBound(selection.LastIndex, n);
    if ~selection.Enabled
        firstIdx = 1;
        lastIdx = n;
    else
        firstIdx = min(firstIdx, n + 1);
        lastIdx = min(lastIdx, n);
    end

    % Slice numbers are stable and intuitive even when scan traversal is
    % reversed: #1 is always the lowest finite Z value.
    sortableZ = zLevels;
    sortableZ(~isfinite(sortableZ)) = Inf;
    [~, lowToHigh] = sort(sortableZ, 'ascend');
    if firstIdx > lastIdx
        indices = zeros(0,1);
    else
        indices = lowToHigh(firstIdx:lastIdx);
        indices = indices(:);
    end

    info = struct('Enabled', selection.Enabled, 'FirstIndex', firstIdx, ...
        'LastIndex', lastIdx, 'AvailableCount', n, 'SelectedCount', numel(indices));
end

function v = sanitizeBound(v, fallback)
    if ~isnumeric(v) || ~isscalar(v) || isnan(v)
        v = fallback;
    elseif isinf(v)
        v = fallback;
    else
        v = max(1, round(double(v)));
    end
end
