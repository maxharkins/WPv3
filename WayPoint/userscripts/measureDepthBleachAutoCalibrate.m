function out = measureDepthBleachAutoCalibrate(hWP, z_um, targetBleachRatio, initialPower_mW, varargin)
%MEASUREDEPTHBLEACHAUTOCALIBRATE Auto-tune power at one depth to match a bleach target.
%
% out = measureDepthBleachAutoCalibrate(hWP, z_um, targetBleachRatio, initialPower_mW, ...)
%
% This helper repeatedly calls measureDepthBleachRaster(...) and adjusts
% power to match a target bleach ratio (typically from a shallow reference).
%
% Required inputs
%   hWP                WayPoint handle
%   z_um               target depth (metadata)
%   targetBleachRatio  target local bleach ratio (0..1, lower = stronger bleach)
%   initialPower_mW    initial burn power guess
%
% Optional name/value inputs
%   'PowerBounds_mW'   ([0.5 120])
%   'Tolerance'        (0.03)
%   'MaxIterations'    (8)
%   'RasterArgs'       ({})   extra args forwarded to measureDepthBleachRaster
%   'Verbose'          (true)

    narginchk(4, inf);
    validateattributes(targetBleachRatio, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
    validateattributes(initialPower_mW, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});

    p = inputParser;
    p.addParameter('PowerBounds_mW', [0.5 120], @(x) isnumeric(x) && isvector(x) && numel(x) == 2 && all(isfinite(x)) && x(1) > 0 && x(2) > x(1));
    p.addParameter('Tolerance', 0.03, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('MaxIterations', 8, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    p.addParameter('RasterArgs', {}, @(x) iscell(x));
    p.addParameter('Verbose', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.parse(varargin{:});
    opts = p.Results;
    opts.Verbose = logical(opts.Verbose);

    loBound = double(opts.PowerBounds_mW(1));
    hiBound = double(opts.PowerBounds_mW(2));

    power = min(max(double(initialPower_mW), loBound), hiBound);
    lowerSolved = NaN; % highest power known to produce ratio > target (needs more bleach)
    upperSolved = NaN; % lowest  power known to produce ratio < target (too much bleach)

    maxIter = round(opts.MaxIterations);
    hist(maxIter, 1) = struct( ...
        'iteration', NaN, ...
        'power_mW', NaN, ...
        'bleachRatio', NaN, ...
        'deltaToTarget', NaN, ...
        'result', []); %#ok<AGROW>

    converged = false;
    stopReason = 'max iterations reached';

    for k = 1:maxIter
        if opts.Verbose
            fprintf('[measureDepthBleachAutoCalibrate] iter %d/%d @ depth %.3f um, power %.3f mW\n', ...
                k, maxIter, z_um, power);
        end

        runResult = measureDepthBleachRaster(hWP, z_um, power, opts.RasterArgs{:});
        ratio = runResult.bleachRatio;

        if ~isfinite(ratio)
            stopReason = 'non-finite bleach ratio';
            hist(k) = makeHistRow(k, power, ratio, NaN, runResult);
            break;
        end

        delta = ratio - targetBleachRatio;
        hist(k) = makeHistRow(k, power, ratio, delta, runResult);

        if opts.Verbose
            fprintf('[measureDepthBleachAutoCalibrate]   bleachRatio=%.5f target=%.5f delta=%+.5f\n', ...
                ratio, targetBleachRatio, delta);
        end

        if abs(delta) <= opts.Tolerance
            converged = true;
            stopReason = sprintf('within tolerance (|delta| <= %.4f)', opts.Tolerance);
            break;
        end

        if ratio > targetBleachRatio
            % Too little bleaching -> need more power.
            lowerSolved = max(lowerSolved, power);
        else
            % Too much bleaching -> need less power.
            if isnan(upperSolved)
                upperSolved = power;
            else
                upperSolved = min(upperSolved, power);
            end
        end

        nextPower = chooseNextPower(power, loBound, hiBound, lowerSolved, upperSolved, ratio, targetBleachRatio);

        if abs(nextPower - power) < 1e-9
            stopReason = 'power update stalled at bound';
            break;
        end

        power = nextPower;
    end

    lastIdx = find(isfinite([hist.iteration]), 1, 'last');
    if isempty(lastIdx)
        lastIdx = 0;
    end

    if lastIdx > 0
        final = hist(lastIdx).result;
        finalPower_mW = hist(lastIdx).power_mW;
        finalBleachRatio = hist(lastIdx).bleachRatio;
    else
        final = [];
        finalPower_mW = NaN;
        finalBleachRatio = NaN;
    end

    out = struct();
    out.depth_um = double(z_um);
    out.targetBleachRatio = double(targetBleachRatio);
    out.tolerance = double(opts.Tolerance);
    out.converged = converged;
    out.stopReason = stopReason;
    out.iterations = hist(1:lastIdx);
    out.finalPower_mW = finalPower_mW;
    out.finalBleachRatio = finalBleachRatio;
    out.finalResult = final;

    if opts.Verbose
        fprintf('[measureDepthBleachAutoCalibrate] done: converged=%d, finalPower=%.3f mW, finalRatio=%.5f\n', ...
            converged, finalPower_mW, finalBleachRatio);
    end
end

function row = makeHistRow(iteration, power_mW, bleachRatio, deltaToTarget, result)
    row = struct();
    row.iteration = iteration;
    row.power_mW = power_mW;
    row.bleachRatio = bleachRatio;
    row.deltaToTarget = deltaToTarget;
    row.result = result;
end

function nextPower = chooseNextPower(currPower, loBound, hiBound, lowerSolved, upperSolved, ratio, target)
    if isfinite(lowerSolved) && isfinite(upperSolved) && upperSolved > lowerSolved
        nextPower = 0.5 * (lowerSolved + upperSolved);
        return;
    end

    if ratio > target
        % Need more bleaching: step up.
        nextPower = min(hiBound, currPower * 1.20);
        if nextPower <= currPower
            nextPower = min(hiBound, currPower + 0.5);
        end
    else
        % Need less bleaching: step down.
        nextPower = max(loBound, currPower * 0.85);
        if nextPower >= currPower
            nextPower = max(loBound, currPower - 0.5);
        end
    end
end
