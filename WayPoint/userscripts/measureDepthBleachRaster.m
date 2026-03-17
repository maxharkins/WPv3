function result = measureDepthBleachRaster(hWP, z_um, power_mW, varargin)
%MEASUREDEPTHBLEACHRASTER Standardized local bleach measurement using a thick raster stripe.
%
% result = measureDepthBleachRaster(hWP, z_um, power_mW, 'Name', value, ...)
%
% Required inputs
%   hWP      WayPoint handle/object with hSI
%   z_um     target depth in microns (metadata only; no stage move)
%   power_mW requested burn power in objective mW
%
% Optional name/value inputs
%   'Zoom'                 (1.3)
%   'StripeLength_um'      (250)
%   'StripeWidth_um'       ([] -> auto)
%   'BeamWidthMultiplier'  (8)
%   'MinStripeWidth_um'    (6)
%   'StripePassSpacing_um' ([] -> beam/2)
%   'StripeYOffset_um'     (0)
%   'PDT_Burn_us'          ([] -> default from SI/WP settings)
%   'PDT_Image_us'         ([] -> unchanged)
%   'SaveImages'           (true)
%   'SaveMAT'              (true)
%   'Verbose'              (true)
%   'EdgeGap_um'           (20)
%   'BGWidth_um'           (15)
%   'UseSnakeRaster'       (true)
%   'OutputSubfolder'      ('DepthBleachRaster')
%   'WaitTimeout_s'        (120)
%   'PollInterval_s'       (0.02)
%   'GrabImageFcn'         ([] -> uses getLatestGrabImage(hSI), intentionally TODO)
%
% Notes
% - Pre and post images are acquired programmatically via hSI.startGrab().
% - getLatestGrabImage(hSI) is intentionally left unimplemented for site-specific SI buffer access.

    narginchk(3, inf);
    validateattributes(z_um, {'numeric'}, {'scalar', 'real', 'finite'}, mfilename, 'z_um', 2);
    validateattributes(power_mW, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0}, mfilename, 'power_mW', 3);

    [hSI, settings] = validateWayPointHandles(hWP);

    p = inputParser;
    p.addParameter('Zoom', 1.3, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('StripeLength_um', 250, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('StripeWidth_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('BeamWidthMultiplier', 8, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('MinStripeWidth_um', 6, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('StripePassSpacing_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('StripeYOffset_um', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    p.addParameter('PDT_Burn_us', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('PDT_Image_us', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    p.addParameter('SaveImages', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('SaveMAT', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('Verbose', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('EdgeGap_um', 20, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    p.addParameter('BGWidth_um', 15, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('UseSnakeRaster', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.addParameter('OutputSubfolder', 'DepthBleachRaster', @(x) ischar(x) || (isstring(x) && isscalar(x)));
    p.addParameter('WaitTimeout_s', 120, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('PollInterval_s', 0.02, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('GrabImageFcn', [], @(x) isempty(x) || isa(x, 'function_handle'));
    p.parse(varargin{:});
    opts = p.Results;

    opts.SaveImages = logical(opts.SaveImages);
    opts.SaveMAT = logical(opts.SaveMAT);
    opts.Verbose = logical(opts.Verbose);
    opts.UseSnakeRaster = logical(opts.UseSnakeRaster);

    beam_um = getSettingScalar(settings, 'BeamWaistDiameter_um', NaN);
    if ~(isfinite(beam_um) && beam_um > 0)
        error('measureDepthBleachRaster:MissingBeamWaist', ...
            'hWP.Settings.BeamWaistDiameter_um must be a finite value > 0 um.');
    end

    if isempty(opts.StripeWidth_um)
        stripeWidth_um = max(opts.BeamWidthMultiplier * beam_um, opts.MinStripeWidth_um);
    else
        stripeWidth_um = double(opts.StripeWidth_um);
    end

    if isempty(opts.StripePassSpacing_um)
        passSpacing_um = beam_um / 2;
    else
        passSpacing_um = double(opts.StripePassSpacing_um);
    end

    stripeSpec = buildStripeSpec(double(opts.StripeLength_um), stripeWidth_um, passSpacing_um, ...
        double(opts.StripeYOffset_um), opts.UseSnakeRaster);

    burnPDT_us = resolvePDTus(hSI, settings, opts.PDT_Burn_us);

    saveCtx = resolveOutputContext(char(string(opts.OutputSubfolder)), double(z_um), ...
        double(power_mW), double(opts.Zoom));

    previous.zoom = getCurrentZoom(hWP, hSI);
    previous.imagePDT_us = getCurrentImagePDTus(hSI);
    restoreOnExit = onCleanup(@() restoreAcqState(hWP, hSI, previous, opts)); %#ok<NASGU>

    if opts.Verbose
        fprintf('[measureDepthBleachRaster] depth=%.3f um, power=%.3f mW, zoom=%.3f\n', ...
            z_um, power_mW, opts.Zoom);
        fprintf('[measureDepthBleachRaster] stripe LxW = %.3f x %.3f um, passes=%d, spacing=%.3f um\n', ...
            stripeSpec.length_um, stripeSpec.width_um, stripeSpec.nPass, stripeSpec.passSpacing_um);
        fprintf('[measureDepthBleachRaster] recommendation: run deep-to-shallow for column measurements.\n');
    end

    applyZoom(hWP, hSI, opts.Zoom, opts.Verbose);
    if ~isempty(opts.PDT_Image_us)
        setImagePDTus(hSI, double(opts.PDT_Image_us));
    end

    startGrabAndWait(hSI, opts.WaitTimeout_s, opts.PollInterval_s);
    imgPre = acquireGrabImage(hSI, opts.GrabImageFcn);

    burnInfo = executeRasterBurn(hWP, stripeSpec, power_mW, burnPDT_us, ...
        'Verbose', opts.Verbose);

    startGrabAndWait(hSI, opts.WaitTimeout_s, opts.PollInterval_s);
    imgPost = acquireGrabImage(hSI, opts.GrabImageFcn);

    imgPre = coerceTo2D(imgPre, 'imgPre');
    imgPost = coerceTo2D(imgPost, 'imgPost');
    if any(size(imgPre) ~= size(imgPost))
        error('measureDepthBleachRaster:ImageSizeMismatch', ...
            'Pre and post image sizes differ: [%s] vs [%s].', ...
            sprintf('%d ', size(imgPre)), sprintf('%d ', size(imgPost)));
    end

    [fovX_um, fovY_um] = resolveFovUm(settings, opts.Zoom);
    [roiMasks, roiMeta] = buildRoiMasks(size(imgPre), fovX_um, fovY_um, stripeSpec, ...
        opts.EdgeGap_um, opts.BGWidth_um);

    metrics = computeBleachMetrics(imgPre, imgPost, roiMasks);

    preImageFile = '';
    postImageFile = '';
    if opts.SaveImages
        preImageFile = fullfile(saveCtx.rawDir, [saveCtx.baseStem '_pre.tif']);
        postImageFile = fullfile(saveCtx.rawDir, [saveCtx.baseStem '_post.tif']);
        saveImageTiff(imgPre, preImageFile);
        saveImageTiff(imgPost, postImageFile);
    end

    matFile = '';
    if opts.SaveMAT
        matFile = fullfile(saveCtx.matDir, [saveCtx.baseStem '.mat']);
        payload = struct();
        payload.images = struct('pre', imgPre, 'post', imgPost);
        payload.roiMasks = roiMasks;
        payload.roiMeta = roiMeta;
        payload.metrics = metrics;
        payload.stripeSpec = stripeSpec;
        payload.burnInfo = burnInfo;
        payload.depth_um = double(z_um);
        payload.power_mW = double(power_mW);
        payload.zoom = double(opts.Zoom);
        payload.timestamp = saveCtx.timestamp;
        payload.options = opts;
        payload.paths = saveCtx;
        save(matFile, 'payload', '-v7.3');
    end

    appendResultsLog(saveCtx.logFile, saveCtx.timestamp, z_um, power_mW, opts.Zoom, beam_um, ...
        stripeSpec, metrics, preImageFile, postImageFile, matFile);

    result = struct();
    result.timestamp = saveCtx.timestamp;
    result.depth_um = double(z_um);
    result.power_mW = double(power_mW);
    result.zoom = double(opts.Zoom);
    result.beamWaist_um = double(beam_um);
    result.stripeLength_um = stripeSpec.length_um;
    result.stripeWidth_um = stripeSpec.width_um;
    result.passSpacing_um = stripeSpec.passSpacing_um;
    result.nPass = stripeSpec.nPass;
    result.I_pre_stripe = metrics.I_pre_stripe;
    result.I_pre_bg = metrics.I_pre_bg;
    result.I_post_stripe = metrics.I_post_stripe;
    result.I_post_bg = metrics.I_post_bg;
    result.stripeChange = metrics.stripeChange;
    result.bgChange = metrics.bgChange;
    result.bleachRatio = metrics.bleachRatio;
    result.postContrast = metrics.postContrast;
    result.preImageFile = preImageFile;
    result.postImageFile = postImageFile;
    result.matFile = matFile;
    result.notes = { ...
        'z_um is metadata only in this script; move stage depth externally before each run.', ...
        'Use fixed XY and local background normalization for depth comparison.', ...
        'Recommendation: acquire deep-to-shallow along a single depth column.'};
end

function [hSI, settings] = validateWayPointHandles(hWP)
    if isempty(hWP)
        error('measureDepthBleachRaster:InvalidhWP', 'hWP is empty.');
    end

    if isa(hWP, 'handle')
        if ~isvalid(hWP)
            error('measureDepthBleachRaster:InvalidhWP', 'hWP is not a valid handle object.');
        end
    end

    if ~isprop(hWP, 'hSI') || isempty(hWP.hSI)
        error('measureDepthBleachRaster:MissingHSI', 'hWP.hSI is required. Start ScanImage first.');
    end
    hSI = hWP.hSI;

    if isa(hSI, 'handle') && ~isvalid(hSI)
        error('measureDepthBleachRaster:InvalidHSI', 'hWP.hSI handle is invalid.');
    end

    if ~isprop(hWP, 'Settings') || ~isstruct(hWP.Settings)
        error('measureDepthBleachRaster:MissingSettings', 'hWP.Settings must exist and be a struct.');
    end
    settings = hWP.Settings;
end

function stripeSpec = buildStripeSpec(stripeLength_um, stripeWidth_um, passSpacing_um, yOffset_um, useSnake)
    validateattributes(stripeLength_um, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
    validateattributes(stripeWidth_um, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});
    validateattributes(passSpacing_um, {'numeric'}, {'scalar', 'real', 'finite', '>', 0});

    xMin = -stripeLength_um / 2;
    xMax = +stripeLength_um / 2;

    yMin = yOffset_um - stripeWidth_um / 2;
    yMax = yOffset_um + stripeWidth_um / 2;

    nPass = max(2, ceil(stripeWidth_um / passSpacing_um));
    yPass = linspace(yMin, yMax, nPass).';

    xPath = zeros(2 * nPass, 1);
    yPath = zeros(2 * nPass, 1);

    for k = 1:nPass
        r0 = 2 * k - 1;
        r1 = 2 * k;

        if useSnake
            leftToRight = mod(k, 2) == 1;
        else
            leftToRight = true;
        end

        if leftToRight
            xPath(r0) = xMin;
            xPath(r1) = xMax;
        else
            xPath(r0) = xMax;
            xPath(r1) = xMin;
        end

        yPath(r0) = yPass(k);
        yPath(r1) = yPass(k);
    end

    if numel(yPass) >= 2
        effectiveSpacing = mean(diff(yPass));
    else
        effectiveSpacing = passSpacing_um;
    end

    stripeSpec = struct();
    stripeSpec.center_x_um = 0;
    stripeSpec.center_y_um = yOffset_um;
    stripeSpec.length_um = stripeLength_um;
    stripeSpec.width_um = stripeWidth_um;
    stripeSpec.passSpacing_um = effectiveSpacing;
    stripeSpec.requestedPassSpacing_um = passSpacing_um;
    stripeSpec.nPass = nPass;
    stripeSpec.x_min_um = xMin;
    stripeSpec.x_max_um = xMax;
    stripeSpec.y_min_um = yMin;
    stripeSpec.y_max_um = yMax;
    stripeSpec.xPath_um = xPath;
    stripeSpec.yPath_um = yPath;
end

function burnPDT_us = resolvePDTus(hSI, settings, requested_us)
    if ~isempty(requested_us)
        burnPDT_us = double(requested_us);
        return;
    end

    burnPDT_us = NaN;

    burnPDT_us = getSettingScalar(settings, 'PixelDwellTime_us', NaN);
    if isfinite(burnPDT_us) && burnPDT_us > 0
        return;
    end

    pdt_ms = getSettingScalar(settings, 'PixelDwellTime_ms', NaN);
    if isfinite(pdt_ms) && pdt_ms > 0
        burnPDT_us = 1000 * pdt_ms;
        return;
    end

    try
        pdt_s = double(hSI.hScan2D.scanPixelTimeMean);
        if isfinite(pdt_s) && pdt_s > 0
            burnPDT_us = 1e6 * pdt_s;
        end
    catch
    end

    if ~(isfinite(burnPDT_us) && burnPDT_us > 0)
        error('measureDepthBleachRaster:MissingBurnPDT', ...
            'Could not resolve PDT_Burn_us. Provide ''PDT_Burn_us'' explicitly.');
    end
end

function saveCtx = resolveOutputContext(outputSubfolder, z_um, power_mW, zoom)
    dayDir = resolveDayFolder();

    rootDir = fullfile(dayDir, outputSubfolder);
    rawDir = fullfile(rootDir, 'raw');
    matDir = fullfile(rootDir, 'mat');
    logsDir = fullfile(rootDir, 'logs');

    ensureDir(rootDir);
    ensureDir(rawDir);
    ensureDir(matDir);
    ensureDir(logsDir);

    t = datetime('now');
    tStamp = char(datetime(t, 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
    tTag = datestr(t, 'yyyymmdd_HHMMSSFFF');

    depthTok = numericToken(z_um, 1);
    powerTok = numericToken(power_mW, 1);
    zoomTok = numericToken(zoom, 1);

    baseStem = sprintf('depth_%sum_power_%smW_zoom_%s_%s', depthTok, powerTok, zoomTok, tTag);

    saveCtx = struct();
    saveCtx.dayDir = dayDir;
    saveCtx.rootDir = rootDir;
    saveCtx.rawDir = rawDir;
    saveCtx.matDir = matDir;
    saveCtx.logsDir = logsDir;
    saveCtx.logFile = fullfile(logsDir, 'depth_bleach_raster_results.txt');
    saveCtx.baseStem = baseStem;
    saveCtx.timestamp = tStamp;
end

function dayDir = resolveDayFolder()
    dayDir = '';

    try
        ctx = wpEnsureDailyExperimentFolder('Create', true, 'DateTime', datetime('now'));
        if isstruct(ctx) && isfield(ctx, 'dayDir') && isfolder(ctx.dayDir)
            dayDir = ctx.dayDir;
            return;
        end
    catch
    end

    zhangBrownDir = '';
    try
        zhangBrownDir = wpFindZhangBrownFolder('StartDir', pwd);
    catch
    end

    if ~isempty(zhangBrownDir)
        experimentsDir = fullfile(zhangBrownDir, 'Experiments');
        ensureDir(experimentsDir);

        yearStr = datestr(now, 'yyyy');
        dayPrefix = [datestr(now, 'yyyy-mm-dd') '_'];

        yearDir = fullfile(experimentsDir, yearStr);
        ensureDir(yearDir);

        d = dir(fullfile(yearDir, [dayPrefix '*']));
        d = d([d.isdir]);

        if isempty(d)
            dayDir = fullfile(yearDir, [dayPrefix 'experiment-name']);
            ensureDir(dayDir);
            return;
        end

        [~, idx] = max([d.datenum]);
        dayDir = fullfile(yearDir, d(idx).name);
        ensureDir(dayDir);
        return;
    end

    dayDir = pwd;
end

function ensureDir(dirPath)
    if ~isfolder(dirPath)
        mkdir(dirPath);
    end
end

function tok = numericToken(v, ndp)
    s = sprintf(['%0.' num2str(ndp) 'f'], double(v));
    s = strrep(s, '-', 'm');
    tok = strrep(s, '.', 'p');
end

function z = getCurrentZoom(hWP, hSI)
    z = NaN;

    try
        z = double(hSI.hRoiManager.scanZoomFactor);
        if isfinite(z) && z > 0
            return;
        end
    catch
    end

    try
        z = double(hSI.hScan2D.scanZoomFactor);
        if isfinite(z) && z > 0
            return;
        end
    catch
    end

    try
        if isprop(hWP, 'hSICtl') && ~isempty(hWP.hSICtl)
            c = hWP.hSICtl.hGUIData.mainControlsV4;
            z = 10 * str2double(c.zoomtens.String) + ...
                1 * str2double(c.zoomones.String) + ...
                0.1 * str2double(c.zoomfrac.String);
        end
    catch
    end
end

function pdt_us = getCurrentImagePDTus(hSI)
    pdt_us = NaN;
    try
        pdt_s = double(hSI.hScan2D.scanPixelTimeMean);
        if isfinite(pdt_s) && pdt_s > 0
            pdt_us = pdt_s * 1e6;
        end
    catch
    end
end

function applyZoom(hWP, hSI, targetZoom, verbose)
    if ~(isfinite(targetZoom) && targetZoom > 0)
        return;
    end

    didSet = false;
    try
        if isprop(hWP, 'hSICtl') && ~isempty(hWP.hSICtl)
            setZoomFactor(hWP.hSICtl, targetZoom);
            didSet = true;
        end
    catch ME
        if verbose
            warning('measureDepthBleachRaster:ZoomSetFailed', ...
                'setZoomFactor failed: %s', ME.message);
        end
    end

    if ~didSet
        try
            hSI.hRoiManager.scanZoomFactor = targetZoom;
            didSet = true;
        catch
        end
    end

    if ~didSet
        try
            hSI.hScan2D.scanZoomFactor = targetZoom;
            didSet = true;
        catch
        end
    end

    if ~didSet
        warning('measureDepthBleachRaster:ZoomNotSet', ...
            'Could not set zoom programmatically; continuing with current zoom.');
    else
        pause(0.2);
    end
end

function setImagePDTus(hSI, pdt_us)
    pdt_s = double(pdt_us) * 1e-6;
    try
        hSI.hScan2D.scanPixelTimeMean = pdt_s;
    catch ME
        error('measureDepthBleachRaster:ImagePDTSetFailed', ...
            'Could not set imaging PDT to %.3f us: %s', pdt_us, ME.message);
    end
end

function restoreAcqState(hWP, hSI, previous, opts)
    if ~isempty(opts.PDT_Image_us) && isfinite(previous.imagePDT_us) && previous.imagePDT_us > 0
        try
            setImagePDTus(hSI, previous.imagePDT_us);
        catch
        end
    end

    if isfinite(previous.zoom) && previous.zoom > 0
        currZoom = getCurrentZoom(hWP, hSI);
        if ~(isfinite(currZoom) && abs(currZoom - previous.zoom) < 1e-6)
            try
                applyZoom(hWP, hSI, previous.zoom, false);
            catch
            end
        end
    end
end

function startGrabAndWait(hSI, timeout_s, poll_s)
    if nargin < 2 || isempty(timeout_s)
        timeout_s = 120;
    end
    if nargin < 3 || isempty(poll_s)
        poll_s = 0.02;
    end

    warnIfExternalTrigger(hSI);
    waitForSIIdle(hSI, timeout_s, poll_s, 'before startGrab');

    if ~ismethod(hSI, 'startGrab')
        error('measureDepthBleachRaster:NoStartGrab', ...
            'hSI.startGrab() is not available in this ScanImage instance.');
    end

    hSI.startGrab();
    waitForSIIdle(hSI, timeout_s, poll_s, 'after startGrab');
end

function warnIfExternalTrigger(hSI)
    persistent warned
    if isempty(warned)
        warned = false;
    end
    if warned
        return;
    end

    try
        if hSI.hScan2D.trigAcqTypeExternal && hSI.extTrigEnable
            warning('measureDepthBleachRaster:ExternalTriggerEnabled', ...
                ['External trigger appears enabled. startGrab() may block waiting ', ...
                 'for hardware trigger events.']);
            warned = true;
        end
    catch
    end
end

function waitForSIIdle(hSI, timeout_s, poll_s, phaseLabel)
    if ~isprop(hSI, 'acqState')
        pause(min(timeout_s, 0.1));
        return;
    end

    t0 = tic;
    while true
        state = safeAcqStateString(hSI);
        if strcmpi(state, 'idle')
            return;
        end

        if toc(t0) > timeout_s
            error('measureDepthBleachRaster:GrabTimeout', ...
                'Timed out waiting for acqState=idle (%s). Current acqState: %s', ...
                phaseLabel, state);
        end
        pause(poll_s);
    end
end

function state = safeAcqStateString(hSI)
    state = 'unknown';
    try
        state = char(string(hSI.acqState));
    catch
    end
end

function img = acquireGrabImage(hSI, grabImageFcn)
    if ~isempty(grabImageFcn)
        img = grabImageFcn(hSI);
    else
        img = getLatestGrabImage(hSI);
    end

    img = coerceTo2D(img, 'grab image');
end

function img = getLatestGrabImage(~)
%GETLATESTGRABIMAGE TODO: implement ScanImage-specific frame retrieval here.
%
% Return requirements:
%   - 2D numeric matrix (single channel image)
%   - latest completed GRAB frame
%
% This helper is intentionally left unimplemented per user request.

    error('measureDepthBleachRaster:getLatestGrabImageUnimplemented', ...
        ['getLatestGrabImage(hSI) is intentionally blank. ', ...
         'Implement your ScanImage frame-buffer accessor here and return a 2D matrix.']);
end

function img = coerceTo2D(imgIn, label)
    if ~(isnumeric(imgIn) || islogical(imgIn))
        error('measureDepthBleachRaster:InvalidImageType', ...
            '%s must be numeric/logical image data.', label);
    end

    img = imgIn;
    if ndims(img) > 2
        sz = size(img);
        trailing = num2cell(ones(1, numel(sz) - 2));
        img = img(:, :, trailing{:});
        img = squeeze(img);
    end

    if ndims(img) ~= 2 || any(size(img) < 2)
        error('measureDepthBleachRaster:InvalidImageSize', ...
            '%s must be a 2D image array.', label);
    end

    img = double(img);
end

function burnInfo = executeRasterBurn(hWP, stripeSpec, power_mW, PDT_Burn_us, varargin)
%EXECUTERASTERBURN Execute the raster burn path in a single isolated helper.

    p = inputParser;
    p.addParameter('Verbose', true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
    p.parse(varargin{:});
    verbose = logical(p.Results.Verbose);

    hSI = hWP.hSI;
    settings = hWP.Settings;

    [hX, hY] = resolveXYGalvoHandles(hSI);
    beamHandle = resolveBeamHandle(hSI);

    [power_pct, power_frac, powerMapNote] = resolveObjectivePower(settings, power_mW);

    if verbose
        fprintf('[measureDepthBleachRaster] burn raster: power=%.3f mW (%.3f%%), PDT=%.3f us\n', ...
            power_mW, power_pct, PDT_Burn_us);
    end

    pdt_s = PDT_Burn_us * 1e-6;
    [playStats, model] = playPreexistingPath(hX, hY, stripeSpec.xPath_um, stripeSpec.yPath_um, pdt_s, ...
        'BeamWaistDiameter_um', getSettingScalar(settings, 'BeamWaistDiameter_um', 0.8), ...
        'BeamHandle', beamHandle, ...
        'PowerFrac', power_frac, ...
        'ParkWhenDone', false);

    burnInfo = struct();
    burnInfo.power_mW = double(power_mW);
    burnInfo.power_pct = double(power_pct);
    burnInfo.power_frac = double(power_frac);
    burnInfo.powerMapNote = powerMapNote;
    burnInfo.PDT_Burn_us = double(PDT_Burn_us);
    burnInfo.pathSpec = stripeSpec;
    burnInfo.playStats = playStats;
    burnInfo.micronsToDegreesModel = model;
end

function [hX, hY] = resolveXYGalvoHandles(hSI)
    hX = [];
    hY = [];

    try
        rs = hSI.hResourceStore.hResources;
        for k = 1:numel(rs)
            r = rs{k};
            if isempty(r)
                continue;
            end

            nm = '';
            try
                nm = char(string(r.name));
            catch
            end
            nm = lower(nm);

            if contains(nm, 'x galvo')
                hX = r;
            elseif contains(nm, 'y galvo')
                hY = r;
            end
        end
    catch
    end

    if isempty(hX) || isempty(hY)
        try
            rs = hSI.hResourceStore.hResources;
            if isempty(hX) && numel(rs) >= 118
                hX = rs{118};
            end
            if isempty(hY) && numel(rs) >= 119
                hY = rs{119};
            end
        catch
        end
    end

    if isempty(hX) || isempty(hY)
        error('measureDepthBleachRaster:GalvoNotFound', ...
            'Could not resolve X/Y galvo handles from ScanImage resources.');
    end
end

function beamHandle = resolveBeamHandle(hSI)
    beamHandle = [];
    try
        beamHandle = hSI.hScan2D.hBeams{1};
    catch
    end
    if isempty(beamHandle)
        error('measureDepthBleachRaster:BeamNotFound', ...
            'Could not resolve beam handle hSI.hScan2D.hBeams{1}.');
    end
end

function [power_pct, power_frac, note] = resolveObjectivePower(settings, power_mW)
    power_pct = NaN;
    note = '';

    hasCal = isfield(settings, 'PockelsCalibration') && isstruct(settings.PockelsCalibration) ...
        && ~isempty(fieldnames(settings.PockelsCalibration));

    if hasCal
        power_pct = objectivePower_mWToPercent(settings.PockelsCalibration, power_mW);
        note = 'Mapped mW to percent using Settings.PockelsCalibration.';
    else
        ref_mW = getSettingScalar(settings, 'Power_mW', NaN);
        ref_pct = getSettingScalar(settings, 'Power_pct', NaN);

        if isfinite(ref_mW) && ref_mW > 0 && isfinite(ref_pct)
            power_pct = ref_pct * (power_mW / ref_mW);
            note = 'Approximate linear mapping from current Settings.Power_mW/Power_pct.';
        elseif power_mW <= 100
            power_pct = power_mW;
            note = 'No calibration found; interpreted power_mW as percent command.';
        else
            error('measureDepthBleachRaster:NoPowerCalibration', ...
                ['Cannot map objective mW to pockels command without calibration. ', ...
                 'Run pockels calibration or provide a <=100 percent-equivalent command.']);
        end
    end

    power_pct = max(0, min(100, double(power_pct)));
    power_frac = power_pct / 100;
end

function pct = objectivePower_mWToPercent(cal, obj_mW)
    obj_W = obj_mW / 1e3;

    if isfield(cal, 'powerObjective_mWToPercent') && isa(cal.powerObjective_mWToPercent, 'function_handle')
        pct = double(cal.powerObjective_mWToPercent(obj_mW));
        return;
    end

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
            error('measureDepthBleachRaster:InvalidCalibration', ...
                'PockelsCalibration is missing "%s".', req{i});
        end
    end

    pcW = obj_W * cal.powerEfficiency;
    pct = powerToPercentFromParams(pcW, cal.A, cal.omega, cal.phi, cal.D);
end

function pct = powerToPercentFromParams(powerW, A, omega, phi, D)
    if abs(A) < eps || abs(omega) < eps
        error('measureDepthBleachRaster:InvalidCalibrationModel', ...
            'Calibration inversion is ill-defined (A or omega too small).');
    end

    pMin = D - abs(A);
    pMax = D + abs(A);
    if powerW < pMin - 1e-9 || powerW > pMax + 1e-9
        error('measureDepthBleachRaster:PowerOutOfRange', ...
            'Requested power is outside calibrated range [%.6g, %.6g] W.', pMin, pMax);
    end

    s = (powerW - D) / A;
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
        error('measureDepthBleachRaster:PowerSolveFailed', ...
            'No valid percent solution in [0, 100].');
    end

    modeled = A .* sin(omega .* candidates + phi) + D;
    [~, idx] = min(abs(modeled - powerW));
    pct = double(candidates(idx));
end

function [fovX_um, fovY_um] = resolveFovUm(settings, zoomVal)
    fovX_um = NaN;
    fovY_um = NaN;

    if isfinite(zoomVal) && zoomVal > 0
        try
            [fovX_um, fovY_um] = zoom2microns(zoomVal);
        catch
        end
    end

    if ~(isfinite(fovX_um) && fovX_um > 0)
        fovX_um = getSettingScalar(settings, 'FOVSize_um', NaN);
    end
    if ~(isfinite(fovY_um) && fovY_um > 0)
        fovY_um = fovX_um;
    end

    if ~(isfinite(fovX_um) && fovX_um > 0 && isfinite(fovY_um) && fovY_um > 0)
        error('measureDepthBleachRaster:MissingFOVCalibration', ...
            'Could not resolve FOV size (zoom2microns/Settings.FOVSize_um).');
    end
end

function [masks, roiMeta] = buildRoiMasks(imgSize, fovX_um, fovY_um, stripeSpec, edgeGap_um, bgWidth_um)
    rows = imgSize(1);
    cols = imgSize(2);

    x_um = ((1:cols) - (cols + 1) / 2) * (fovX_um / cols);
    y_um = ((1:rows) - (rows + 1) / 2) * (fovY_um / rows);
    [X, Y] = meshgrid(x_um, y_um);

    halfLen = stripeSpec.length_um / 2;
    halfStripeW = stripeSpec.width_um / 2;
    y0 = stripeSpec.center_y_um;

    stripeMask = abs(X - 0) <= halfLen & abs(Y - y0) <= halfStripeW;

    yUpperCtr = y0 + halfStripeW + edgeGap_um + bgWidth_um / 2;
    yLowerCtr = y0 - halfStripeW - edgeGap_um - bgWidth_um / 2;

    upperBgMask = abs(X - 0) <= halfLen & abs(Y - yUpperCtr) <= bgWidth_um / 2;
    lowerBgMask = abs(X - 0) <= halfLen & abs(Y - yLowerCtr) <= bgWidth_um / 2;
    bgMask = upperBgMask | lowerBgMask;

    if nnz(stripeMask) < 10
        error('measureDepthBleachRaster:StripeMaskTooSmall', ...
            'Stripe ROI has too few pixels (%d). Check FOV/zoom/stripe settings.', nnz(stripeMask));
    end

    if nnz(bgMask) < 10
        error('measureDepthBleachRaster:BGMaskTooSmall', ...
            'Background ROI has too few pixels (%d). Reduce BGWidth_um/EdgeGap_um or stripe width.', nnz(bgMask));
    end

    masks = struct();
    masks.stripe = stripeMask;
    masks.bgUpper = upperBgMask;
    masks.bgLower = lowerBgMask;
    masks.bg = bgMask;

    roiMeta = struct();
    roiMeta.fovX_um = fovX_um;
    roiMeta.fovY_um = fovY_um;
    roiMeta.stripeRect_um = [ ...
        -halfLen, stripeSpec.x_max_um, ...
        y0 - halfStripeW, y0 + halfStripeW];
    roiMeta.bgUpperRect_um = [ ...
        -halfLen, stripeSpec.x_max_um, ...
        yUpperCtr - bgWidth_um / 2, yUpperCtr + bgWidth_um / 2];
    roiMeta.bgLowerRect_um = [ ...
        -halfLen, stripeSpec.x_max_um, ...
        yLowerCtr - bgWidth_um / 2, yLowerCtr + bgWidth_um / 2];
end

function metrics = computeBleachMetrics(imgPre, imgPost, roiMasks)
    I_pre_stripe = maskedMean(imgPre, roiMasks.stripe);
    I_pre_bg = maskedMean(imgPre, roiMasks.bg);

    I_post_stripe = maskedMean(imgPost, roiMasks.stripe);
    I_post_bg = maskedMean(imgPost, roiMasks.bg);

    stripeChange = safeRatio(I_post_stripe, I_pre_stripe);
    bgChange = safeRatio(I_post_bg, I_pre_bg);
    bleachRatio = safeRatio(stripeChange, bgChange);
    postContrast = safeRatio(I_post_bg - I_post_stripe, I_post_bg);

    metrics = struct();
    metrics.I_pre_stripe = I_pre_stripe;
    metrics.I_pre_bg = I_pre_bg;
    metrics.I_post_stripe = I_post_stripe;
    metrics.I_post_bg = I_post_bg;
    metrics.stripeChange = stripeChange;
    metrics.bgChange = bgChange;
    metrics.bleachRatio = bleachRatio;
    metrics.postContrast = postContrast;
end

function m = maskedMean(img, mask)
    values = img(mask);
    values = values(isfinite(values));
    if isempty(values)
        m = NaN;
    else
        m = mean(values);
    end
end

function r = safeRatio(num, den)
    if ~isfinite(num) || ~isfinite(den) || abs(den) < eps
        r = NaN;
    else
        r = num / den;
    end
end

function saveImageTiff(img, outPath)
    [outDir, ~, ~] = fileparts(outPath);
    if ~isempty(outDir)
        ensureDir(outDir);
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
        imgD = imgD ./ mx;
    end
    imgU16 = uint16(round(imgD * 65535));
    imwrite(imgU16, outPath, 'tif');
end

function appendResultsLog(logPath, timestamp, z_um, power_mW, zoom, beam_um, stripeSpec, metrics, preFile, postFile, matFile)
    [logDir, ~, ~] = fileparts(logPath);
    if ~isempty(logDir)
        ensureDir(logDir);
    end

    writeHeader = true;
    if exist(logPath, 'file') == 2
        d = dir(logPath);
        writeHeader = d.bytes == 0;
    end

    fid = fopen(logPath, 'a');
    if fid < 0
        error('measureDepthBleachRaster:LogOpenFailed', 'Failed to open log file: %s', logPath);
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    if writeHeader
        fprintf(fid, ['timestamp\tdepth_um\tpower_mW\tzoom\tbeam_um\tstripe_length_um\tstripe_width_um\t' ...
            'pass_spacing_um\tn_pass\tI_pre_stripe\tI_pre_bg\tI_post_stripe\tI_post_bg\t' ...
            'stripe_change\tbg_change\tbleach_ratio\tpost_contrast\tpre_image_file\tpost_image_file\tmat_file\n']);
    end

    fprintf(fid, ['%s\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%d\t' ...
        '%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%.9f\t%s\t%s\t%s\n'], ...
        sanitizeTSV(timestamp), ...
        z_um, power_mW, zoom, beam_um, stripeSpec.length_um, stripeSpec.width_um, stripeSpec.passSpacing_um, stripeSpec.nPass, ...
        metrics.I_pre_stripe, metrics.I_pre_bg, metrics.I_post_stripe, metrics.I_post_bg, ...
        metrics.stripeChange, metrics.bgChange, metrics.bleachRatio, metrics.postContrast, ...
        sanitizeTSV(preFile), sanitizeTSV(postFile), sanitizeTSV(matFile));
end

function s = sanitizeTSV(x)
    s = char(string(x));
    s = strrep(s, sprintf('\t'), ' ');
    s = strrep(s, sprintf('\n'), ' ');
    s = strrep(s, sprintf('\r'), ' ');
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
