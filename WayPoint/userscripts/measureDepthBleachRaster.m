function result = measureDepthBleachRaster(hWP, z_um, power_mW, varargin)
%MEASUREDEPTHBLEACHRASTER Measure local bleaching at depth using a raster burn stripe.
%
%   result = measureDepthBleachRaster(hWP, z_um, power_mW)
%   result = measureDepthBleachRaster(..., 'Name', value, ...)
%
% Required inputs
%   hWP      : WayPoint app object
%   z_um     : target depth in microns (local/mask frame)
%   power_mW : commanded objective power in mW
%
% Optional Name/Value parameters
%   'StripeLength_um'      (250)
%   'StripeWidth_um'       (auto: max(8*beam, 6), snapped to beam multiples)
%   'EdgeBuffer_um'        (30)
%   'Zoom'                 (1.3)
%   'PDT'                  (default hWP.Settings.PixelDwellTime_ms, in ms)
%   'SaveImages'           (true)
%   'StripePassSpacing_um' (deprecated override; canonical spacing is beam/2)

    if nargin < 3
        error('measureDepthBleachRaster requires hWP, z_um, and power_mW.');
    end

    validateattributes(z_um, {'numeric'}, {'scalar', 'real', 'finite'}, mfilename, 'z_um', 2);
    validateattributes(power_mW, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'power_mW', 3);

    if isempty(hWP) || ~isprop(hWP, 'hSI') || isempty(hWP.hSI)
        error('hWP.hSI is required. Start ScanImage and initialize WayPoint first.');
    end
    if ~isprop(hWP, 'Settings') || ~isstruct(hWP.Settings)
        error('hWP.Settings is missing or invalid.');
    end

    p = inputParser;
    p.addParameter('StripeLength_um', 250, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('StripeWidth_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('EdgeBuffer_um', 30, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    p.addParameter('Zoom', 1.3, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('PDT', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('SaveImages', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('StripePassSpacing_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.parse(varargin{:});
    opts = p.Results;
    opts.SaveImages = logical(opts.SaveImages);

    beam_um = getSettingScalar(hWP.Settings, 'BeamWaistDiameter_um', NaN);
    if ~isfinite(beam_um) || beam_um <= 0
        error('hWP.Settings.BeamWaistDiameter_um must be finite and > 0.');
    end

    % Optional zoom update through existing WP helper.
    if isfinite(opts.Zoom) && opts.Zoom > 0
        try
            if isprop(hWP, 'hSICtl') && ~isempty(hWP.hSICtl)
                setZoomFactor(hWP.hSICtl, opts.Zoom);
                pause(0.2);
            end
        catch ME
            warning('measureDepthBleachRaster:ZoomSetFailed', ...
                'Could not set zoom to %.3f: %s', opts.Zoom, ME.message);
        end
    end

    [fovX_um, fovY_um] = resolveFovUm(hWP.Settings, opts.Zoom);
    usableX_um = fovX_um - 2 * opts.EdgeBuffer_um;
    usableY_um = fovY_um - 2 * opts.EdgeBuffer_um;
    if usableX_um <= beam_um || usableY_um <= beam_um
        error('EdgeBuffer_um is too large for current FOV (%.3f x %.3f um).', fovX_um, fovY_um);
    end

    stripeLength_um = min(double(opts.StripeLength_um), usableX_um);

    if isempty(opts.StripeWidth_um)
        stripeWidthTarget_um = max(8 * beam_um, 6);
    else
        stripeWidthTarget_um = double(opts.StripeWidth_um);
    end
    stripeWidthTarget_um = min(stripeWidthTarget_um, usableY_um);
    stripeWidth_um = snapUpToMultiple(stripeWidthTarget_um, beam_um);
    if stripeWidth_um > usableY_um
        stripeWidth_um = max(beam_um, floor(usableY_um / beam_um) * beam_um);
    end
    if stripeWidth_um <= 0
        error('Invalid stripe width after FOV constraints.');
    end

    stripePassSpacing_um = wpRasterSpacingFromBeamWaist(beam_um);
    if ~isempty(opts.StripePassSpacing_um)
        requestedSpacing_um = double(opts.StripePassSpacing_um);
        tol = max(1e-12, eps(stripePassSpacing_um) * 10);
        if abs(requestedSpacing_um - stripePassSpacing_um) > tol
            warning('measureDepthBleachRaster:StripePassSpacingForced', ...
                'Ignoring StripePassSpacing_um=%.6g. Using BeamWaistDiameter_um/2 = %.6g um.', ...
                requestedSpacing_um, stripePassSpacing_um);
        end
    end
    if stripePassSpacing_um <= 0
        error('StripePassSpacing_um must be > 0.');
    end

    nPasses = max(2, ceil(stripeWidth_um / stripePassSpacing_um));
    [xBurn_um, yBurn_um] = buildSnakeRasterPath(stripeLength_um, nPasses, stripePassSpacing_um);

    [hX, hY] = getXYGalvos(hWP);
    if isempty(hX) || isempty(hY)
        error('Could not resolve X/Y galvo handles.');
    end

    beamHandle = [];
    try
        beamHandle = hWP.hSI.hScan2D.hBeams{1};
    catch
        error('Could not resolve beam handle hWP.hSI.hScan2D.hBeams{1}.');
    end

    [powerFrac, resolvedPct] = resolveObjectivePowerToFraction(hWP.Settings, power_mW);

    if isprop(hWP, 'Power_Pct_Edit_Field')
        hWP.Power_Pct_Edit_Field.Value = resolvedPct;
    elseif isprop(hWP, 'Power_Edit_Field')
        hWP.Power_Edit_Field.Value = resolvedPct;
    end
    if isprop(hWP, 'Power_mW_Edit_Field')
        hWP.Power_mW_Edit_Field.Value = power_mW;
    end
    hWP.Settings.Power_pct = resolvedPct;
    hWP.Settings.Power_mW = power_mW;

    if isempty(opts.PDT)
        pdt_ms = getSettingScalar(hWP.Settings, 'PixelDwellTime_ms', NaN);
    else
        pdt_ms = double(opts.PDT);
    end
    if ~isfinite(pdt_ms) || pdt_ms <= 0
        error('PDT must be provided, or hWP.Settings.PixelDwellTime_ms must be valid.');
    end
    pdt_s = pdt_ms / 1000;

    zWorld_um = double(z_um) + getMaskZOffset(hWP);
    moveToDepthUm(hWP, zWorld_um);

    io = resolveOutputContext();
    if ~isfolder(io.imageDir)
        mkdir(io.imageDir);
    end

    stamp = datestr(datetime('now'), 'yyyy-mm-dd HH:MM:SS.FFF');
    runTag = wpSanitizeLabel(sprintf('depthBleachRaster_%s_z%.2f_p%.2f', ...
        datestr(now, 'yyyymmdd_HHMMSSFFF'), z_um, power_mW));

    prePath = '';
    postPath = '';
    if opts.SaveImages
        prePath = fullfile(io.imageDir, [runTag '_pre.tif']);
        postPath = fullfile(io.imageDir, [runTag '_post.tif']);
    end

    img_pre = captureSingleFrame(hWP);
    if opts.SaveImages
        saveImageTiff(img_pre, prePath);
    end

    playPreexistingPath(hX, hY, xBurn_um, yBurn_um, pdt_s, ...
        'BeamWaistDiameter_um', beam_um, ...
        'BeamHandle', beamHandle, ...
        'PowerFrac', powerFrac, ...
        'StartHold_s', 0.004, ...
        'EndHold_s', 0.004, ...
        'ParkWhenDone', false);

    img_post = captureSingleFrame(hWP);
    if opts.SaveImages
        saveImageTiff(img_post, postPath);
    end

    metrics = computeBleachMetrics( ...
        img_pre, img_post, fovX_um, fovY_um, stripeLength_um, stripeWidth_um, opts.EdgeBuffer_um);

    appendBleachLog(io.logPath, stamp, z_um, power_mW, beam_um, stripeWidth_um, stripeLength_um, ...
        metrics.preStripe, metrics.postStripe, metrics.preBG, metrics.postBG, metrics.bleachRatio, ...
        prePath, postPath);

    result = struct();
    result.depth_um = double(z_um);
    result.power_mW = double(power_mW);
    result.beam_um = double(beam_um);
    result.stripeWidth_um = double(stripeWidth_um);
    result.preStripe = metrics.preStripe;
    result.postStripe = metrics.postStripe;
    result.preBG = metrics.preBG;
    result.postBG = metrics.postBG;
    result.bleachRatio = metrics.bleachRatio;
    result.imageFiles = struct('pre', prePath, 'post', postPath, 'log', io.logPath);
    result.contrast = metrics.contrast;
    result.stripeLength_um = stripeLength_um;
    result.passSpacing_um = stripePassSpacing_um;
    result.nPasses = nPasses;
    result.power_pct = resolvedPct;
    result.zWorld_um = zWorld_um;
    result.roi = metrics.roi;
    result.hooks = struct( ...
        'measureDepthBleachSweep', 'TODO', ...
        'fitDepthPowerCurve', 'TODO', ...
        'generatePowerRamp', 'TODO');
end

function [fovX_um, fovY_um] = resolveFovUm(settings, zoomVal)
    fovX_um = getSettingScalar(settings, 'FOVSize_um', NaN);
    fovY_um = fovX_um;

    if nargin >= 2 && isfinite(zoomVal) && zoomVal > 0
        try
            [fovX_um, fovY_um] = zoom2microns(zoomVal);
            return;
        catch
            % Fall back to Settings.FOVSize_um below.
        end
    end

    if ~isfinite(fovX_um) || fovX_um <= 0
        fovX_um = 512;
        fovY_um = 512;
    end
end

function val = getSettingScalar(settings, fieldName, fallback)
    val = fallback;
    if isstruct(settings) && isfield(settings, fieldName)
        v = settings.(fieldName);
        if isnumeric(v) && isscalar(v) && isfinite(v)
            val = double(v);
        end
    end
end

function out = snapUpToMultiple(val, step)
    if ~isfinite(val) || val <= 0
        out = step;
        return;
    end
    out = ceil(val / step) * step;
    if ~isfinite(out) || out <= 0
        out = step;
    end
end

function [x_um, y_um] = buildSnakeRasterPath(length_um, nPasses, spacing_um)
    xMin = -length_um / 2;
    xMax = length_um / 2;

    span_um = (nPasses - 1) * spacing_um;
    yStart = -span_um / 2;
    yVals = yStart + (0:nPasses-1) * spacing_um;

    x_um = zeros(2 * nPasses, 1);
    y_um = zeros(2 * nPasses, 1);

    for i = 1:nPasses
        rowA = 2 * i - 1;
        rowB = 2 * i;
        if mod(i, 2) == 1
            x_um(rowA) = xMin;
            x_um(rowB) = xMax;
        else
            x_um(rowA) = xMax;
            x_um(rowB) = xMin;
        end
        y_um(rowA) = yVals(i);
        y_um(rowB) = yVals(i);
    end
end

function [hX, hY] = getXYGalvos(hWP)
    hX = [];
    hY = [];

    try
        rs = hWP.hSI.hResourceStore.hResources;
        for k = 1:numel(rs)
            r = rs{k};
            if isempty(r) || ~isobject(r)
                continue;
            end
            nm = '';
            try
                nm = string(r.name);
            catch
            end
            nml = lower(char(nm));
            if contains(nml, 'x galvo')
                hX = r;
            elseif contains(nml, 'y galvo')
                hY = r;
            end
        end
    catch
    end

    if isempty(hX) || isempty(hY)
        try
            rs = hWP.hSI.hResourceStore.hResources;
            if isempty(hX) && numel(rs) >= 118
                hX = rs{118};
            end
            if isempty(hY) && numel(rs) >= 119
                hY = rs{119};
            end
        catch
        end
    end
end

function [powerFrac, pct] = resolveObjectivePowerToFraction(settings, power_mW)
    pct = NaN;
    hasCal = isfield(settings, 'PockelsCalibration') && isstruct(settings.PockelsCalibration) ...
        && ~isempty(fieldnames(settings.PockelsCalibration));

    if hasCal
        pct = objectivePower_mWToPercent(settings.PockelsCalibration, power_mW);
    else
        ref_mW = getSettingScalar(settings, 'Power_mW', NaN);
        ref_pct = getSettingScalar(settings, 'Power_pct', NaN);

        if isfinite(ref_mW) && ref_mW > 0 && isfinite(ref_pct)
            pct = ref_pct * (power_mW / ref_mW);
            warning('measureDepthBleachRaster:ApproxPowerMap', ...
                ['Using approximate linear mW->pct mapping from current Settings only. ' ...
                 'Run pockelsCellPowerCalibration for accurate objective mW control.']);
        elseif power_mW >= 0 && power_mW <= 100
            pct = power_mW;
            warning('measureDepthBleachRaster:AssumePercent', ...
                'No calibration found. Interpreting power_mW=%.3f as power percent.', power_mW);
        else
            error(['Cannot map objective mW to pockels percent without a calibration. ' ...
                   'Run pockelsCellPowerCalibration or provide a <=100 percent value.']);
        end
    end

    pct = max(0, min(100, double(pct)));
    powerFrac = pct / 100;
end

function pct = objectivePower_mWToPercent(cal, obj_mW)
    obj_W = obj_mW / 1e3;
    if isfield(cal, 'powerObjective_WToPercent') && isa(cal.powerObjective_WToPercent, 'function_handle')
        pct = double(cal.powerObjective_WToPercent(obj_W));
        return;
    end
    if isfield(cal, 'objectivePowerToPCPower') && isa(cal.objectivePowerToPCPower, 'function_handle') && ...
       isfield(cal, 'powerToPercent') && isa(cal.powerToPercent, 'function_handle')
        pcW = cal.objectivePowerToPCPower(obj_W);
        pct = double(cal.powerToPercent(pcW));
        return;
    end

    req = {'A', 'omega', 'phi', 'D', 'powerEfficiency'};
    for i = 1:numel(req)
        if ~isfield(cal, req{i})
            error('PockelsCalibration is missing "%s".', req{i});
        end
    end
    pcW = obj_W * cal.powerEfficiency;
    pct = powerToPercentFromParams(pcW, cal.A, cal.omega, cal.phi, cal.D);
end

function percent = powerToPercentFromParams(power, A, omega, phi, D)
    if abs(A) < eps
        error('Calibration amplitude is too small; inversion is ill-defined.');
    end
    if abs(omega) < eps
        error('Calibration omega is too small; inversion is ill-defined.');
    end

    Pmin = D - abs(A);
    Pmax = D + abs(A);
    tol = 1e-9;
    if power < (Pmin - tol) || power > (Pmax + tol)
        error('Requested power outside calibrated downstream range [%.6g, %.6g] W.', Pmin, Pmax);
    end

    s = (power - D) / A;
    s = min(max(s, -1), 1);
    alpha = asin(s);

    b1 = (alpha - phi) / omega;
    b2 = (pi - alpha - phi) / omega;
    period = abs(2 * pi / omega);

    nMin = floor((0 - max([b1 b2])) / period) - 1;
    nMax = ceil((100 - min([b1 b2])) / period) + 1;
    k = nMin:nMax;

    candidates = [b1 + k * period, b2 + k * period];
    candidates = candidates(candidates >= 0 & candidates <= 100);
    if isempty(candidates)
        error('No valid percent solution found in [0, 100].');
    end

    modeled = A .* sin(omega .* candidates + phi) + D;
    [~, idx] = min(abs(modeled - power));
    percent = double(candidates(idx));
end

function offset_um = getMaskZOffset(hWP)
    offset_um = 0;
    try
        if isprop(hWP, 'hMask') && ~isempty(hWP.hMask) && isprop(hWP.hMask, 'Position')
            pos = hWP.hMask.Position;
            if isnumeric(pos) && numel(pos) >= 3 && isfinite(pos(3))
                offset_um = double(pos(3));
            end
        end
    catch
    end
end

function moveToDepthUm(hWP, zWorld_um)
    currZ = NaN;
    try
        currZ = double(hWP.hSI.hMotors.samplePosition(:,3));
    catch
    end
    if isfinite(currZ)
        delta = abs(currZ - zWorld_um);
        if delta >= 800
            error('Refusing Z move: current %.3f um, target %.3f um (delta=%.3f um).', currZ, zWorld_um, delta);
        end
    end

    hWP.hSI.hMotors.moveSample([0 0 zWorld_um]);
    t0 = tic;
    while hWP.hSI.hMotors.moveInProgress
        pause(0.02);
        if toc(t0) > 30
            warning('measureDepthBleachRaster:ZMoveTimeout', ...
                'Z move did not report completion within 30 s.');
            break;
        end
    end
end

function io = resolveOutputContext()
    io = struct();
    io.dayDir = pwd;
    io.imageDir = pwd;
    io.logPath = fullfile(pwd, 'depth_bleach_raster.txt');

    zhangBrownDir = '';
    try
        zhangBrownDir = wpFindZhangBrownFolder('StartDir', pwd);
    catch
        zhangBrownDir = '';
    end

    if isempty(zhangBrownDir)
        return;
    end

    try
        ctx = wpEnsureDailyExperimentFolder('Create', true, 'DateTime', datetime('now'));
        io.dayDir = ctx.dayDir;
        if isfield(ctx, 'subdirs') && isfield(ctx.subdirs, 'raw')
            io.imageDir = ctx.subdirs.raw;
        else
            io.imageDir = ctx.dayDir;
        end
        io.logPath = fullfile(ctx.dayDir, 'depth_bleach_raster.txt');
        return;
    catch
        io.dayDir = makeDailyFolderFallback(zhangBrownDir);
        io.imageDir = io.dayDir;
        io.logPath = fullfile(io.dayDir, 'depth_bleach_raster.txt');
    end
end

function dayDir = makeDailyFolderFallback(zhangBrownDir)
    experimentsDir = fullfile(zhangBrownDir, 'Experiments');
    if ~isfolder(experimentsDir)
        mkdir(experimentsDir);
    end

    yearStr = datestr(now, 'yyyy');
    dayPrefix = [datestr(now, 'yyyy-mm-dd') '_'];
    yearDir = fullfile(experimentsDir, yearStr);
    if ~isfolder(yearDir)
        mkdir(yearDir);
    end

    d = dir(fullfile(yearDir, [dayPrefix '*']));
    d = d([d.isdir]);
    if isempty(d)
        dayDir = fullfile(yearDir, [dayPrefix 'experiment-name']);
        if ~isfolder(dayDir)
            mkdir(dayDir);
        end
        return;
    end

    [~, idx] = max([d.datenum]);
    dayDir = fullfile(yearDir, d(idx).name);
end

function img = captureSingleFrame(hWP)
    hSI = hWP.hSI;
    img = [];
    tried = {};

    try
        if ismethod(hSI, 'abort')
            hSI.abort();
            pause(0.05);
        end
    catch
    end

    if ismethod(hSI, 'startGrab')
        tried{end+1} = 'hSI.startGrab'; %#ok<AGROW>
        try
            hSI.startGrab();
            waitForIdleState(hSI, 20);
            img = extractLatestFrame(hSI);
            if ~isempty(img)
                return;
            end
        catch
        end
    end

    if isprop(hWP, 'hSICtl') && ~isempty(hWP.hSICtl)
        tried{end+1} = 'hSICtl grabOneButton'; %#ok<AGROW>
        try
            notify(hWP.hSICtl.hGUIData.mainControlsV4.grabOneButton, 'Action');
            waitForIdleState(hSI, 20);
            img = extractLatestFrame(hSI);
            if ~isempty(img)
                return;
            end
        catch
        end
    end

    if ismethod(hSI, 'startFocus')
        tried{end+1} = 'hSI.startFocus'; %#ok<AGROW>
        try
            hSI.startFocus();
            pause(0.25);
            if ismethod(hSI, 'abort')
                hSI.abort();
            end
            waitForIdleState(hSI, 10);
            img = extractLatestFrame(hSI);
            if ~isempty(img)
                return;
            end
        catch
        end
    end

    if isempty(tried)
        tried = {'no known ScanImage acquire method found'};
    end
    error('Could not acquire frame from ScanImage. Tried: %s', strjoin(tried, ', '));
end

function waitForIdleState(hSI, timeout_s)
    if nargin < 2
        timeout_s = 10;
    end

    if ~isprop(hSI, 'acqState')
        pause(min(timeout_s, 0.2));
        return;
    end

    t0 = tic;
    while toc(t0) < timeout_s
        st = '';
        try
            st = lower(char(string(hSI.acqState)));
        catch
        end
        if contains(st, 'idle')
            return;
        end
        pause(0.05);
    end
end

function img = extractLatestFrame(hSI)
    img = [];

    if isprop(hSI, 'hDisplay')
        try
            img = extractFromContainer(hSI.hDisplay);
            if ~isempty(img)
                return;
            end
        catch
        end
    end

    img = extractFromContainer(hSI);
end

function img = extractFromContainer(container)
    img = [];
    if isempty(container)
        return;
    end

    candidates = { ...
        'lastFrame', ...
        'lastFrameData', ...
        'lastAcquiredFrame', ...
        'lastAcquiredData', ...
        'frameData', ...
        'currentFrame', ...
        'stripeDataBuffer', ...
        'rollingStripeDataBuffer'};

    for i = 1:numel(candidates)
        [ok, value] = tryGetMember(container, candidates{i});
        if ~ok
            continue;
        end
        img = coerceTo2DImage(value, 0);
        if ~isempty(img)
            return;
        end
    end

    methodCandidates = {'getLastFrame', 'getCurrentFrame'};
    if isobject(container)
        for i = 1:numel(methodCandidates)
            m = methodCandidates{i};
            if ismethod(container, m)
                try
                    value = container.(m)();
                    img = coerceTo2DImage(value, 0);
                    if ~isempty(img)
                        return;
                    end
                catch
                end
            end
        end
    end
end

function [ok, value] = tryGetMember(container, memberName)
    ok = false;
    value = [];
    try
        if isstruct(container) && isfield(container, memberName)
            value = container.(memberName);
            ok = true;
            return;
        end
        if isobject(container) && isprop(container, memberName)
            value = container.(memberName);
            ok = true;
        end
    catch
    end
end

function img = coerceTo2DImage(value, depth)
    img = [];
    if nargin < 2
        depth = 0;
    end
    if depth > 4 || isempty(value)
        return;
    end

    if isnumeric(value) || islogical(value)
        arr = value;
        if ndims(arr) == 2 && all(size(arr) > 1)
            img = double(arr);
            return;
        end
        if ndims(arr) >= 3
            idx = repmat({1}, 1, ndims(arr) - 2);
            try
                arr2 = arr(:, :, idx{:});
            catch
                arr2 = arr(:, :, 1);
            end
            arr2 = squeeze(arr2);
            if ndims(arr2) == 2 && all(size(arr2) > 1)
                img = double(arr2);
                return;
            end
        end
        return;
    end

    if iscell(value)
        for i = 1:numel(value)
            img = coerceTo2DImage(value{i}, depth + 1);
            if ~isempty(img)
                return;
            end
        end
        return;
    end

    if isstruct(value)
        fn = {'image', 'img', 'frame', 'data', 'imageData', 'frameData'};
        for i = 1:numel(fn)
            if isfield(value, fn{i})
                img = coerceTo2DImage(value.(fn{i}), depth + 1);
                if ~isempty(img)
                    return;
                end
            end
        end
        return;
    end

    if isobject(value)
        img = extractFromContainer(value);
    end
end

function saveImageTiff(img, outPath)
    [outDir, ~, ~] = fileparts(outPath);
    if ~isempty(outDir) && ~isfolder(outDir)
        mkdir(outDir);
    end

    if isa(img, 'uint8') || isa(img, 'uint16') || isa(img, 'uint32')
        imwrite(img, outPath, 'tif');
        return;
    end

    if islogical(img)
        imwrite(uint8(img) * 255, outPath, 'tif');
        return;
    end

    imgD = double(img);
    imgD = imgD - min(imgD(:));
    mx = max(imgD(:));
    if mx > 0
        imgD = imgD / mx;
    end
    imgU16 = uint16(round(imgD * 65535));
    imwrite(imgU16, outPath, 'tif');
end

function metrics = computeBleachMetrics(imgPre, imgPost, fovX_um, fovY_um, stripeLength_um, stripeWidth_um, edgeBuffer_um)
    pre = coerceTo2DImage(imgPre, 0);
    post = coerceTo2DImage(imgPost, 0);
    if isempty(pre) || isempty(post)
        error('Could not coerce pre/post images to 2D arrays.');
    end
    if any(size(pre) ~= size(post))
        error('Pre and post images have different sizes.');
    end

    [rows, cols] = size(pre);
    x_um = ((1:cols) - (cols + 1) / 2) * (fovX_um / cols);
    y_um = ((1:rows) - (rows + 1) / 2) * (fovY_um / rows);
    [X, Y] = meshgrid(x_um, y_um);

    halfLen = stripeLength_um / 2;
    halfW = stripeWidth_um / 2;
    stripeMask = abs(X) <= halfLen & abs(Y) <= halfW;

    bgOffset_um = max(30, edgeBuffer_um);
    pixY_um = fovY_um / rows;
    maxOffset_um = (fovY_um / 2) - halfW - pixY_um;
    if maxOffset_um > halfW
        bgOffset_um = min(bgOffset_um, 0.9 * maxOffset_um);
    else
        bgOffset_um = halfW + 2 * pixY_um;
    end

    bgTopMask = abs(X) <= halfLen & abs(Y - bgOffset_um) <= halfW;
    bgBottomMask = abs(X) <= halfLen & abs(Y + bgOffset_um) <= halfW;
    bgMask = bgTopMask | bgBottomMask;

    if nnz(bgMask) < 25
        shellHalfW = min(fovY_um / 2, halfW + max(20, edgeBuffer_um));
        bgMask = abs(X) <= halfLen & abs(Y) <= shellHalfW & ~stripeMask;
    end

    globalMask = ~stripeMask;

    preStripe = maskedMean(pre, stripeMask);
    postStripe = maskedMean(post, stripeMask);
    preBG = maskedMean(pre, bgMask);
    postBG = maskedMean(post, bgMask);
    preGlobal = maskedMean(pre, globalMask);
    postGlobal = maskedMean(post, globalMask);

    stripeChange = safeRatio(postStripe, preStripe);
    bgChange = safeRatio(postBG, preBG);
    bleachRatio = safeRatio(stripeChange, bgChange);
    contrast = safeRatio(postBG - postStripe, postBG);

    metrics = struct();
    metrics.preStripe = preStripe;
    metrics.postStripe = postStripe;
    metrics.preBG = preBG;
    metrics.postBG = postBG;
    metrics.preGlobal = preGlobal;
    metrics.postGlobal = postGlobal;
    metrics.bleachRatio = bleachRatio;
    metrics.contrast = contrast;
    metrics.roi = struct( ...
        'stripe', [-halfLen, halfLen, -halfW, halfW], ...
        'bgTop', [-halfLen, halfLen, bgOffset_um-halfW, bgOffset_um+halfW], ...
        'bgBottom', [-halfLen, halfLen, -bgOffset_um-halfW, -bgOffset_um+halfW], ...
        'bgOffset_um', bgOffset_um);
end

function m = maskedMean(img, mask)
    v = img(mask);
    v = v(isfinite(v));
    if isempty(v)
        m = NaN;
    else
        m = mean(v);
    end
end

function r = safeRatio(num, den)
    if ~isfinite(num) || ~isfinite(den) || abs(den) < eps
        r = NaN;
    else
        r = num / den;
    end
end

function appendBleachLog(logPath, timestamp, depth_um, power_mW, beam_um, stripeWidth_um, stripeLength_um, ...
        inner_pre, inner_post, bg_pre, bg_post, bleach_ratio, image_pre, image_post)
    [logDir, ~, ~] = fileparts(logPath);
    if ~isempty(logDir) && ~isfolder(logDir)
        mkdir(logDir);
    end

    writeHeader = true;
    if exist(logPath, 'file') == 2
        d = dir(logPath);
        writeHeader = d.bytes == 0;
    end

    fid = fopen(logPath, 'a');
    if fid < 0
        error('Could not open log file for append: %s', logPath);
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    if writeHeader
        fprintf(fid, ['timestamp\tdepth_um\tpower_mW\tbeam_waist_um\tstripe_width_um\tstripe_length_um\t' ...
                      'inner_pre\tinner_post\tbg_pre\tbg_post\tbleach_ratio\timage_file_pre\timage_file_post\n']);
    end

    fprintf(fid, '%s\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%s\t%s\n', ...
        sanitizeTSV(timestamp), depth_um, power_mW, beam_um, stripeWidth_um, stripeLength_um, ...
        inner_pre, inner_post, bg_pre, bg_post, bleach_ratio, ...
        sanitizeTSV(image_pre), sanitizeTSV(image_post));
end

function out = sanitizeTSV(in)
    out = char(string(in));
    out = strrep(out, sprintf('\t'), ' ');
    out = strrep(out, sprintf('\n'), ' ');
    out = strrep(out, sprintf('\r'), ' ');
end
