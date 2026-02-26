function prepSequence(app)

    app.ImagingType = 'ablation';

    % % --- Get quantization factors
    % if ~isempty(app.hMask.hNodes.BasePoints)
    %     minResDist = findMinResolvableDistance(app.hMask.hNodes.BasePoints);
    % else
    %     minResDist = [];
    % end
    % [app, isSimilar] = getQuantFactor(app, minResDist);

    tileSpacing = app.Settings.FOVSize_um - 2*app.Tile_Overlap_Edit_Field.Value*[1 1];

    % --- If nothing is active, exit
    if isempty(app.hMask.hTri.BasePoints) && isempty(app.hMask.hNodes.BasePoints)
        return
    end


    %% ============================================================
    % 3) Build Stage Path ONLY
    % =============================================================
    
    if app.hStacks.isMeshScan
        geomPts = app.hMask.hTri.TransformedPoints;
    else
        geomPts = app.hMask.hNodes.TransformedPoints;
    end
    

    
    % --- Base stage path (tile centers, mask-local)
    baseStagePath = getStagePath( ...
        app, ...
        geomPts, ...
        tileSpacing, ...
        'ablation');
    
    % --- Apply mask position ONLY to stage path
    maskOffsetXY = app.hMask.Position(1:2);
    
    app.aPath.Coordinates = baseStagePath + [maskOffsetXY, 0];

    % Do NOT recreate app.hStacks here. If it exists, just update fields.
    if ~isempty(app.hStacks) && isvalid(app.hStacks)
        app.hStacks.StagePath         = app.aPath.Coordinates;
        app.hStacks.FramesPerSlice    = app.Settings.FramesPerSlice;
        app.hStacks.PixelDwellTime_ms = app.Settings.PixelDwellTime_ms;
        app.hStacks.Power_pct         = app.Settings.Power_pct;
    else
        % Only create if truly missing
        app.hStacks = Stacks(app, false);
    end    
    refreshPlot(app);
    disp('Prep complete (stage path only).');


    %% ============================================================
    % Final Updates
    % =============================================================
    refreshPlot(app)
end

function [app, isSimilar] = getQuantFactor(app, minimumResolvableDistance)
    if nargin < 2 || isempty(minimumResolvableDistance)
        minimumResolvableDistance = [0 0 0];
        xy_quantPrompt_str = num2str(app.Settings.QuantFactorXY_um);
        z_quantPrompt_str = num2str(app.Settings.QuantFactorZ_um);
    else 
        xy_quantPrompt_double = min(minimumResolvableDistance(1:2));
        if isnan(xy_quantPrompt_double) % if its NaN, then just use the original quant factor
            xy_quantPrompt_str = num2str(app.Settings.QuantFactorXY_um);
        else
            xy_quantPrompt_str = num2str(xy_quantPrompt_double);
        end
        
        z_quantPrompt_double = minimumResolvableDistance(3);
        if isnan(z_quantPrompt_double) % if its NaN, then just use the original quant factor
            z_quantPrompt_str = num2str(app.Settings.QuantFactorZ_um);
        else
            z_quantPrompt_str = num2str(z_quantPrompt_double);
        end
    end
        

    prompt   = {'Enter XY Distance (µm):', 'Enter Z Distance (µm):'};
    dlgtitle = 'Input Distances Between Points';
    dims     = [1 35];

    definput = { ...
        xy_quantPrompt_str, ...
        z_quantPrompt_str};

    answer = inputdlg(prompt, dlgtitle, dims, definput);

    if isempty(answer)
        isSimilar = true;
        return
    end

    newXY = str2double(answer{1});
    newZ  = str2double(answer{2});

    isSimilar = ...
        (newXY == app.Settings.QuantFactorXY_um) && ...
        (newZ  == app.Settings.QuantFactorZ_um);

    app.Settings.QuantFactorXY_um = newXY;
    app.Settings.QuantFactorZ_um  = newZ;

    app.XY_Quant_Factor_Edit_Field.Value = newXY;
    app.Z_Quant_Factor_Edit_Field.Value  = newZ;


end
% --- local helper (place at end of file or as separate utility)
function [qNodes, info] = quantizeNodesPhaseAware(nodes, qXY, qZ)
    % Quantize Nx3 nodes onto voxel lattice with step sizes qXY, qZ.
    % Uses integer index space + phase selection to minimize XY collapse.
    %
    % Outputs:
    %   qNodes : unique quantized nodes (Nx3)
    %   info   : struct diagnostics

    assert(size(nodes,2) == 3, 'nodes must be Nx3');

    N0 = size(nodes,1);

    % Candidate phase choices per axis (try a few reasonable anchors)
    x = nodes(:,1); y = nodes(:,2); z = nodes(:,3);

    candX = unique([0, mean(x), median(x), min(x), max(x)]);
    candY = unique([0, mean(y), median(y), min(y), max(y)]);
    candZ = unique([0, mean(z), median(z), min(z), max(z)]);

    % We'll choose phase for X,Y to maximize number of unique XY bins
    bestScore = -inf;
    bestPhi   = [0 0 0];
    bestIdxXY = [];
    bestIdxZ  = [];

    % Precompute for speed: divide by step once
    xOver = x / qXY;
    yOver = y / qXY;
    zOver = z / qZ;

    for px = candX
        pxOver = px / qXY;
        idxX = round(xOver - pxOver);

        for py = candY
            pyOver = py / qXY;
            idxY = round(yOver - pyOver);

            % Score = number of unique XY bins (primary objective)
            idxXY = [idxX idxY];
            score = size(unique(idxXY, 'rows'), 1);

            if score > bestScore
                bestScore = score;
                bestPhi(1:2) = [px py];
                bestIdxXY = idxXY;
            end
        end
    end

    % For Z, phase matters less for "row skipping" in XY, but keep it stable.
    % Choose phase that maximizes unique Z bins (or just use median).
    bestScoreZ = -inf;
    bestPz = 0;
    bestIdxZ_local = [];
    for pz = candZ
        pzOver = pz / qZ;
        idxZ = round(zOver - pzOver);
        scoreZ = numel(unique(idxZ));
        if scoreZ > bestScoreZ
            bestScoreZ = scoreZ;
            bestPz = pz;
            bestIdxZ_local = idxZ;
        end
    end
    bestPhi(3) = bestPz;
    bestIdxZ   = bestIdxZ_local;

    % Unique in integer index space (most robust)
    idxAll = [bestIdxXY bestIdxZ];
    idxAllU = unique(idxAll, 'rows');

    % Convert back to coordinate space using chosen phase
    qNodes = zeros(size(idxAllU));
    qNodes(:,1) = (idxAllU(:,1) * qXY) + bestPhi(1);
    qNodes(:,2) = (idxAllU(:,2) * qXY) + bestPhi(2);
    qNodes(:,3) = (idxAllU(:,3) * qZ ) + bestPhi(3);

    % Diagnostics
    info = struct();
    info.numPointsIn = N0;
    info.numPointsOut = size(qNodes,1);
    info.numUniqueXY_in  = size(unique(nodes(:,1:2), 'rows'), 1);
    info.numUniqueXY_out = size(unique(qNodes(:,1:2), 'rows'), 1);
    info.phaseXYZ = bestPhi;

    % Guardrail: warn if you are collapsing a lot of XY points
    collapseFrac = 1 - (info.numUniqueXY_out / max(1, info.numUniqueXY_in));
    if collapseFrac > 0.10
        warning('Quantization collapsed %.1f%% of unique XY points. QuantFactorXY may be too large.', 100*collapseFrac);
    end
end