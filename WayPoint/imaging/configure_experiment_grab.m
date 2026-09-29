function out = configure_experiment_grab(experimentName, varargin)
% configure_experiment_grab
% Configure ScanImage save path + filename for experiment grabs.
%
% This utility does the following:
%   1) sets save root to:
%      <BaseDir>/Zhang&Brown/Experiments/<year>/<YYYY-MM-DD>_<experimentName>/raw
%      and creates sibling log folder:
%      <BaseDir>/Zhang&Brown/Experiments/<year>/<YYYY-MM-DD>_<experimentName>/log
%   2) enables saving (hSI.hChannels.loggingEnable = true)
%   3) ensures channel 3 is in hSI.hChannels.channelSave
%   4) builds metadata-rich filename stem from current acquisition settings
%   5) writes extra metadata into TIFF ImageDescription via
%      grab_and_save_with_metadata (optional)
%   6) writes a setup log file to the experiment log folder
%
% Usage examples:
%   cfg = configure_experiment_grab('cortex-window');
%   cfg = configure_experiment_grab('cortex-window', ...
%       'BaseDir', '/Volumes/file directory');
%   cfg = configure_experiment_grab('cortex-window', ...
%       'BaseName', 'mouse12_predrug');
%   cfg = configure_experiment_grab('cortex-window', ...
%       'BaseName', 'mouse12_predrug', 'BaseNameOnly', true);
%   out = configure_experiment_grab('cortex-window', 'RunGrab', true);
%
% Name-value options:
%   'HSI'            : ScanImage handle (default: evalin('base','hSI'))
%   'BaseDir'        : base mount path (e.g. '/Volumes/file directory')
%                      If empty, function attempts auto-detection.
%   'YearFolder'     : numeric/string year folder (default: current year)
%   'BaseName'       : custom file stem seed (separate from folder name)
%   'BaseNameOnly'   : if true, use only BaseName/experimentName as stem
%                      (no auto metadata suffixes)
%   'EnsureChannel'  : channel index to force-save (default: 3)
%   'RunGrab'        : if true, start one grab and patch TIFF metadata
%   'ExtraMetadata'  : struct/string custom metadata to merge
%   'TimeoutSec'     : timeout for optional RunGrab (default: 120)
%
% Output:
%   out struct with fields:
%   experimentDir, rawDir, logDir, saveDir, baseNameRequested,
%   baseNameResolved, metadata, cfg, setupLog
%   and (if RunGrab=true) out.grab containing grab_and_save_with_metadata output.

    ip = inputParser();
    ip.addRequired('experimentName', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('HSI', [], @(x)isempty(x) || isobject(x));
    ip.addParameter('BaseDir', '', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('YearFolder', year(datetime('today')), @(x) ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 2000 && x <= 3000) || ...
        (ischar(x) || (isstring(x) && isscalar(x))));
    ip.addParameter('BaseName', '', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('BaseNameOnly', false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
    ip.addParameter('EnsureChannel', 3, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && mod(x,1)==0);
    ip.addParameter('RunGrab', false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
    ip.addParameter('ExtraMetadata', struct(), @(x)isstruct(x) || ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('TimeoutSec', 120, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    ip.parse(experimentName, varargin{:});

    experimentName = char(string(ip.Results.experimentName));
    hSI = resolveHSI(ip.Results.HSI);
    ensureChannel = double(ip.Results.EnsureChannel);
    runGrab = logical(ip.Results.RunGrab);
    baseNameOnly = logical(ip.Results.BaseNameOnly);
    timeoutSec = double(ip.Results.TimeoutSec);
    yearFolder = normalizeYearFolder(ip.Results.YearFolder);
    baseNameInput = strtrim(char(string(ip.Results.BaseName)));

    applySaveSettings(hSI, ensureChannel);

    experimentsRoot = resolveExperimentsRoot(hSI, char(string(ip.Results.BaseDir)), yearFolder);
    folderName = buildExperimentFolderName(experimentName);
    experimentDir = fullfile(experimentsRoot, folderName);
    rawDir = fullfile(experimentDir, 'raw');
    logDir = fullfile(experimentDir, 'log');
    ensureDir(experimentDir);
    ensureDir(rawDir);
    ensureDir(logDir);
    saveDir = rawDir;

    md = collectAcqMetadata(hSI);
    md = mergeMetadata(md, normalizeUserMetadata(ip.Results.ExtraMetadata));
    md.experiment_name = experimentName;
    md.experiment_folder = folderName;
    md.experiments_root = experimentsRoot;
    md.experiment_dir = experimentDir;
    md.raw_dir = rawDir;
    md.log_dir = logDir;
    md.base_name_input = baseNameInput;
    md.base_name_only = baseNameOnly;
    md.generated_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    md.tiff_note = ['ScanImage native metadata stays in TIFF tags; ', ...
        'CustomMetadataJSON is appended by grab_and_save_with_metadata.'];

    if isempty(baseNameInput)
        stemSeed = experimentName;
    else
        stemSeed = baseNameInput;
    end

    if baseNameOnly
        requestedStem = sanitizeStem(stemSeed);
    else
        requestedStem = buildStemFromMetadata(stemSeed, md);
    end
    cfg = configure_grab_basename(saveDir, requestedStem, 'HSI', hSI, 'UserMetadata', md);

    out = struct();
    out.experimentDir = experimentDir;
    out.rawDir = rawDir;
    out.logDir = logDir;
    out.saveDir = saveDir;
    out.baseNameRequested = requestedStem;
    out.baseNameResolved = cfg.baseNameResolved;
    out.baseNameInput = baseNameInput;
    out.baseNameOnly = baseNameOnly;
    out.metadata = cfg.metadata;
    out.cfg = cfg;
    out.channelSave = hSI.hChannels.channelSave;
    out.saveEnabled = logical(hSI.hChannels.loggingEnable);

    if runGrab
        out.grab = grab_and_save_with_metadata( ...
            'HSI', hSI, ...
            'Config', cfg, ...
            'Metadata', md, ...
            'TimeoutSec', timeoutSec);
    end

    out.setupLog = writeSetupLog(logDir, out);
end

function hSI = resolveHSI(hSI)
    if isempty(hSI)
        if ~evalin('base', "exist('hSI','var')")
            error('configure_experiment_grab:hSIMissing', ...
                'hSI was not found in base workspace. Start ScanImage first.');
        end
        hSI = evalin('base', 'hSI');
    end
    assert(isvalid(hSI), 'configure_experiment_grab:InvalidHSI', 'hSI handle is invalid.');
end

function yearFolder = normalizeYearFolder(v)
    if isnumeric(v)
        yearFolder = sprintf('%d', round(v));
    else
        yearFolder = regexprep(char(string(v)), '\s+', '');
        if isempty(yearFolder)
            yearFolder = sprintf('%d', year(datetime('today')));
        end
    end
end

function applySaveSettings(hSI, ensureChannel)
    hSI.hChannels.loggingEnable = true;

    try
        nAvail = double(hSI.hChannels.channelsAvailable);
    catch
        nAvail = nan;
    end

    if isfinite(nAvail) && ensureChannel > nAvail
        warning('configure_experiment_grab:ChannelUnavailable', ...
            'Requested channel %d exceeds channelsAvailable (%d). Keeping existing channelSave.', ...
            ensureChannel, nAvail);
        return;
    end

    chanSave = hSI.hChannels.channelSave;
    if isempty(chanSave)
        chanSave = ensureChannel;
    else
        chanSave = unique([chanSave(:)' ensureChannel], 'stable');
    end
    hSI.hChannels.channelSave = chanSave;
end

function experimentsRoot = resolveExperimentsRoot(hSI, baseDir, yearFolder)
    baseDir = strtrim(baseDir);

    candidates = {};

    if ~isempty(baseDir)
        candidates = [candidates deriveExperimentsRootCandidates(baseDir, yearFolder)];
    end

    envBase = strtrim(getenv('SCANIMAGE_EXPERIMENTS_BASEDIR'));
    if ~isempty(envBase)
        candidates = [candidates deriveExperimentsRootCandidates(envBase, yearFolder)];
    end

    try
        currentLogPath = strtrim(char(string(hSI.hScan2D.logFilePath)));
    catch
        currentLogPath = '';
    end
    if ~isempty(currentLogPath)
        inferred = inferRootFromCurrentPath(currentLogPath, yearFolder);
        if ~isempty(inferred)
            candidates{end+1} = inferred;
        end
    end

    volumeBases = discoverVolumeBases();
    fromVolumes = cell(1, numel(volumeBases));
    for i = 1:numel(volumeBases)
        fromVolumes{i} = deriveExperimentsRootCandidates(volumeBases{i}, yearFolder);
    end
    if ~isempty(fromVolumes)
        candidates = [candidates fromVolumes{:}];
    end

    candidates = unique(candidates, 'stable');
    candidates(cellfun(@isempty, candidates)) = [];

    for i = 1:numel(candidates)
        if exist(candidates{i}, 'dir')
            experimentsRoot = candidates{i};
            return;
        end
    end

    if ~isempty(baseDir) && ~isempty(candidates)
        experimentsRoot = candidates{1};
        mkdir(experimentsRoot);
        return;
    end

    details = strjoin(candidates, newline);
    if isempty(details)
        details = '(no candidates generated)';
    end

    error('configure_experiment_grab:BaseDirNotFound', ...
        ['Could not locate experiments root automatically.\n' ...
         'Pass BaseDir explicitly, e.g. ''/Volumes/file directory''.\n\n' ...
         'Tried:\n%s'], details);
end

function out = deriveExperimentsRootCandidates(basePath, yearFolder)
    out = {};
    if isempty(basePath)
        return;
    end

    p = normalizePath(basePath);
    if isempty(p)
        return;
    end

    zhangRoot = fullfile('Zhang&Brown');
    expTail = fullfile('Zhang&Brown', 'Experiments');

    if endsWithPath(p, fullfile(expTail, yearFolder))
        out{end+1} = p;
        return;
    end

    if endsWithPath(p, expTail)
        out{end+1} = fullfile(p, yearFolder);
        return;
    end

    if endsWithPath(p, zhangRoot)
        out{end+1} = fullfile(p, 'Experiments', yearFolder);
        return;
    end

    if endsWithPath(p, 'Experiments')
        out{end+1} = fullfile(p, yearFolder);
        out{end+1} = fullfile(p, '..', expTail, yearFolder);
        return;
    end

    out{end+1} = fullfile(p, expTail, yearFolder);
end

function inferred = inferRootFromCurrentPath(currentPath, yearFolder)
    inferred = '';
    p = normalizePath(currentPath);
    if isempty(p)
        return;
    end

    marker = normalizePath(fullfile('Zhang&Brown', 'Experiments'));
    pNorm = normalizePath(p);
    idx = strfind(lower(pNorm), lower(marker));
    if isempty(idx)
        return;
    end

    prefix = pNorm(1:idx(1)-1);
    if isempty(prefix)
        prefix = filesep;
    end
    inferred = fullfile(prefix, marker, yearFolder);
end

function bases = discoverVolumeBases()
    bases = { ...
        '/Volumes/file directory', ...
        '/Volumes/File Directory', ...
        '/Volumes/FileDirectory', ...
        '/Volumes/file_directory' ...
    };

    d = dir('/Volumes');
    for i = 1:numel(d)
        if d(i).isdir && ~strcmp(d(i).name, '.') && ~strcmp(d(i).name, '..')
            bases{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
        end
    end

    bases = unique(bases, 'stable');
end

function tf = endsWithPath(pathIn, tail)
    p = normalizePath(pathIn);
    t = normalizePath(tail);
    if isempty(p) || isempty(t)
        tf = false;
        return;
    end

    if strcmpi(p, t)
        tf = true;
        return;
    end

    tf = endsWith(lower(p), [lower(filesep) lower(t)]);
end

function p = normalizePath(pathIn)
    p = char(string(pathIn));
    p = strtrim(p);
    if isempty(p)
        return;
    end
    p = regexprep(p, '[\\/]+', filesep);
    while numel(p) > 1 && (p(end) == '\' || p(end) == '/')
        p(end) = [];
    end
end

function folderName = buildExperimentFolderName(experimentName)
    d = datetime('today');
    datePart = sprintf('%04d-%02d-%02d', year(d), month(d), day(d));
    expPart = sanitizeToken(experimentName, '-');
    folderName = sprintf('%s_%s', datePart, expPart);
end

function stem = buildStemFromMetadata(experimentName, md)
    parts = {};
    parts{end+1} = sanitizeToken(experimentName, '-');

    if isfiniteField(md, 'zoom_factor')
        parts{end+1} = ['zm' numToken(md.zoom_factor, 2)];
    end

    if isfiniteField(md, 'pixel_dwell_time_ns')
        parts{end+1} = ['pdt' numToken(md.pixel_dwell_time_ns, 1) 'ns'];
    end

    if isfiniteField(md, 'pixels_per_line')
        parts{end+1} = sprintf('w%spx', numToken(md.pixels_per_line, 0));
    end

    if isfiniteField(md, 'lines_per_frame')
        parts{end+1} = sprintf('h%spx', numToken(md.lines_per_frame, 0));
    end

    if isfield(md, 'z_depth_token') && ~isempty(md.z_depth_token)
        parts{end+1} = md.z_depth_token;
    end

    if isfield(md, 'stack_sequence_token') && ~isempty(md.stack_sequence_token)
        parts{end+1} = md.stack_sequence_token;
    end

    if isfield(md, 'power_token') && ~isempty(md.power_token)
        parts{end+1} = md.power_token;
    end

    if isfield(md, 'channel_save_token') && ~isempty(md.channel_save_token)
        parts{end+1} = md.channel_save_token;
    end

    if isfiniteField(md, 'scan_frame_rate_hz')
        parts{end+1} = ['fps' numToken(md.scan_frame_rate_hz, 2)];
    end

    stem = strjoin(parts, '_');
    stem = sanitizeStem(stem);
    stem = truncateStem(stem, 180);
end

function md = collectAcqMetadata(hSI)
    md = struct();

    md.zoom_factor = safeEval(@()double(hSI.hRoiManager.scanZoomFactor), nan);
    md.pixel_dwell_time_s = getPixelDwellTime(hSI);
    md.pixel_dwell_time_ns = md.pixel_dwell_time_s * 1e9;
    md.pixels_per_line = safeEval(@()double(hSI.hRoiManager.pixelsPerLine), nan);
    md.lines_per_frame = safeEval(@()double(hSI.hRoiManager.linesPerFrame), nan);
    md.scan_frame_rate_hz = safeEval(@()double(hSI.hRoiManager.scanFrameRate), nan);
    md.line_period_s = safeEval(@()double(hSI.hRoiManager.linePeriod), nan);
    md.log_average_factor = safeEval(@()double(hSI.hScan2D.logAverageFactor), nan);
    md.bidirectional = safeEval(@()logical(hSI.hScan2D.bidirectional), false);

    md.save_enabled = safeEval(@()logical(hSI.hChannels.loggingEnable), false);
    md.channel_save = safeEval(@()double(hSI.hChannels.channelSave(:)'), []);
    md.channel_display = safeEval(@()double(hSI.hChannels.channelDisplay(:)'), []);
    md.channel_save_token = channelsToken(md.channel_save);

    md.current_z_um = getCurrentDepthUm(hSI);
    [stackToken, stackString, stackStart, stackEnd, stackStep, zsUnique] = getStackSummary(hSI);
    md.stack_sequence_token = stackToken;
    md.stack_sequence_human = stackString;
    md.stack_start_um = stackStart;
    md.stack_end_um = stackEnd;
    md.stack_step_um = stackStep;
    md.stack_zs_um = zsUnique;
    md.z_depth_token = zDepthToken(md.current_z_um);

    md.stack_enabled = safeEval(@()logical(hSI.hStackManager.enable), false);
    md.stack_mode = safeEnumText(safeEval(@()hSI.hStackManager.stackMode, []));
    md.stack_definition = safeEnumText(safeEval(@()hSI.hStackManager.stackDefinition, []));
    md.stack_num_slices = safeEval(@()double(hSI.hStackManager.actualNumSlices), nan);
    md.stack_frames_per_slice = safeEval(@()double(hSI.hStackManager.framesPerSlice), nan);
    md.stack_num_volumes = safeEval(@()double(hSI.hStackManager.actualNumVolumes), nan);

    powerFractions = safeEval(@()double(hSI.hBeams.powerFractions(:)'), []);
    powerFractions = powerFractions(isfinite(powerFractions));
    md.pockels_transmission_fraction = powerFractions;
    md.pockels_transmission_percent = powerFractions * 100;
    md.power_token = powerToken(powerFractions);

    md.log_file_path = safeEval(@()char(string(hSI.hScan2D.logFilePath)), '');
    md.log_file_stem = safeEval(@()char(string(hSI.hScan2D.logFileStem)), '');
    md.log_file_counter = safeEval(@()double(hSI.hScan2D.logFileCounter), nan);
    md.acq_state = safeEval(@()char(string(hSI.acqState)), '');
end

function pdt = getPixelDwellTime(hSI)
    pdt = safeEval(@()double(hSI.hScan2D.scanPixelTimeMean), nan);
    if ~isfinite(pdt)
        pdt = safeEval(@()double(hSI.hScan2D.pixelBinFactor) / double(hSI.hScan2D.sampleRate), nan);
    end
end

function z = getCurrentDepthUm(hSI)
    z = nan;
    try
        pos = hSI.hMotors.samplePosition;
        if ~isempty(pos) && numel(pos) >= 3 && isfinite(pos(3))
            z = double(pos(3));
            return;
        end
    catch
    end

    try
        zs = hSI.hStackManager.zs;
        if ~isempty(zs) && isfinite(zs(1))
            z = double(zs(1));
            return;
        end
    catch
    end
end

function [token, human, zStart, zEnd, zStep, zsUnique] = getStackSummary(hSI)
    token = '';
    human = '';
    zStart = nan;
    zEnd = nan;
    zStep = nan;
    zsUnique = [];

    stackEnabled = safeEval(@()logical(hSI.hStackManager.enable), false);
    if ~stackEnabled
        return;
    end

    zs = safeEval(@()double(hSI.hStackManager.zs(:)'), []);
    zs = zs(isfinite(zs));
    if isempty(zs)
        return;
    end

    zs = round(zs, 3);
    zsUnique = unique(zs, 'stable');
    if isempty(zsUnique)
        return;
    end

    zStart = zsUnique(1);
    zEnd = zsUnique(end);

    if isscalar(zsUnique)
        token = ['stk' numToken(zStart, 3) 'um'];
        human = sprintf('z=%s um', numTokenReadable(zStart, 3));
        return;
    end

    dz = diff(zsUnique);
    isUniform = all(abs(dz - dz(1)) < 1e-6);

    if isUniform
        zStep = dz(1);
        token = sprintf('stk%sstep%sto%sum', ...
            numToken(zStart, 3), numToken(zStep, 3), numToken(zEnd, 3));
        human = sprintf('z=%s:%s:%s um', ...
            numTokenReadable(zStart, 3), ...
            numTokenReadable(zStep, 3), ...
            numTokenReadable(zEnd, 3));
    else
        zList = arrayfun(@(x)numToken(x, 3), zsUnique, 'UniformOutput', false);
        if numel(zList) > 8
            shortList = strjoin(zList(1:8), '-');
            shortList = sprintf('%s-plus%d', shortList, numel(zList)-8);
        else
            shortList = strjoin(zList, '-');
        end
        token = ['stklist' shortList];
        human = sprintf('z=[%s] um', strjoin(arrayfun(@(x)numTokenReadable(x,3), zsUnique, 'UniformOutput', false), ','));
    end

    token = sanitizeToken(token, '_');
end

function token = zDepthToken(z)
    if ~isfinite(z)
        token = '';
        return;
    end
    token = ['z' numToken(z, 3) 'um'];
end

function token = powerToken(powerFractions)
    if isempty(powerFractions)
        token = 'powNA';
        return;
    end

    bits = arrayfun(@(v)numToken(v, 3), powerFractions, 'UniformOutput', false);
    if numel(bits) > 4
        token = sprintf('pow%s-plus%d', strjoin(bits(1:4), '-'), numel(bits)-4);
    else
        token = ['pow' strjoin(bits, '-')];
    end
    token = sanitizeToken(token, '_');
end

function token = channelsToken(channels)
    if isempty(channels)
        token = 'chNA';
        return;
    end
    channels = unique(channels(:)', 'stable');
    bits = arrayfun(@(v)sprintf('%d', round(v)), channels, 'UniformOutput', false);
    token = ['ch' strjoin(bits, '-')];
end

function tf = isfiniteField(s, fieldName)
    tf = isfield(s, fieldName) && isnumeric(s.(fieldName)) && isscalar(s.(fieldName)) && isfinite(s.(fieldName));
end

function s = numToken(v, digits)
    if nargin < 2
        digits = 3;
    end
    fmt = sprintf('%%.%df', digits);
    s = sprintf(fmt, v);
    s = regexprep(s, '\.?0+$', '');
    s = strrep(s, '-', 'm');
    s = strrep(s, '.', 'p');
end

function s = numTokenReadable(v, digits)
    if nargin < 2
        digits = 3;
    end
    fmt = sprintf('%%.%df', digits);
    s = sprintf(fmt, v);
    s = regexprep(s, '\.?0+$', '');
end

function token = sanitizeToken(token, spaceReplacement)
    token = char(string(token));
    token = strtrim(token);
    if isempty(token)
        token = 'experiment';
        return;
    end

    token = regexprep(token, '\s+', spaceReplacement);
    token = regexprep(token, '[/\\\*:\?"<>\|]', '_');
    token = regexprep(token, '[^A-Za-z0-9._\-+]', '_');
    token = regexprep(token, '_{2,}', '_');
    token = regexprep(token, '-{2,}', '-');
    token = regexprep(token, '^[_.\-]+', '');
    token = regexprep(token, '[_.\-]+$', '');

    if isempty(token)
        token = 'experiment';
    end
end

function stem = sanitizeStem(stem)
    stem = sanitizeToken(stem, '-');
    stem = regexprep(stem, '\.(tif|tiff)$', '', 'ignorecase');
    if isempty(stem)
        stem = 'grab';
    end
end

function stem = truncateStem(stem, maxLen)
    if numel(stem) <= maxLen
        return;
    end
    keep = max(16, maxLen - 10);
    prefix = stem(1:keep);
    checksum = simpleChecksum(stem);
    stem = sprintf('%s_%s', prefix, checksum);
end

function s = simpleChecksum(txt)
    v = double(char(txt));
    if isempty(v)
        s = '000000';
        return;
    end
    c = mod(sum(v .* (1:numel(v))), 16^6);
    s = lower(dec2hex(c, 6));
end

function val = safeEval(fcn, defaultVal)
    try
        val = fcn();
    catch
        val = defaultVal;
        return;
    end

    if isempty(val)
        val = defaultVal;
    end
end

function txt = safeEnumText(v)
    txt = '';
    if isempty(v)
        return;
    end

    try
        txt = char(v.char);
        return;
    catch
    end

    try
        txt = char(string(v));
    catch
        txt = '';
    end
end

function ensureDir(dirPath)
    if ~exist(dirPath, 'dir')
        mkdir(dirPath);
    end
end

function logInfo = writeSetupLog(logDir, out)
    ensureDir(logDir);

    ts = datetime('now');
    tsFile = char(datetime(ts, 'Format', 'yyyyMMdd_HHmmss_SSS'));
    tsHuman = char(datetime(ts, 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));

    baseName = ['configure_experiment_grab_' tsFile];
    jsonPath = fullfile(logDir, [baseName '.json']);
    txtPath = fullfile(logDir, [baseName '.txt']);

    logData = struct();
    logData.timestamp_local = tsHuman;
    logData.experiment_dir = getFieldOr(out, 'experimentDir', '');
    logData.raw_dir = getFieldOr(out, 'rawDir', '');
    logData.log_dir = getFieldOr(out, 'logDir', '');
    logData.save_dir = getFieldOr(out, 'saveDir', '');
    logData.base_name_requested = getFieldOr(out, 'baseNameRequested', '');
    logData.base_name_resolved = getFieldOr(out, 'baseNameResolved', '');
    logData.channel_save = getFieldOr(out, 'channelSave', []);
    logData.save_enabled = getFieldOr(out, 'saveEnabled', false);
    logData.metadata = getFieldOr(out, 'metadata', struct());

    if isfield(out, 'grab')
        logData.grab = struct();
        logData.grab.files = getFieldOr(out.grab, 'files', {});
        logData.grab.counter_used = getFieldOr(out.grab, 'counterUsed', nan);
    end

    fid = -1;
    try
        fid = fopen(jsonPath, 'w');
        assert(fid > 0, 'configure_experiment_grab:LogOpenFailed', 'Could not open JSON log file.');
        fwrite(fid, jsonencode(logData), 'char');
        fclose(fid);
        fid = -1;
        jsonOk = true;
    catch
        if fid > 0
            fclose(fid);
        end
        jsonOk = false;
    end

    fid = fopen(txtPath, 'w');
    if fid > 0
        fprintf(fid, 'configure_experiment_grab log\n');
        fprintf(fid, 'timestamp_local: %s\n', tsHuman);
        fprintf(fid, 'experiment_dir: %s\n', char(string(logData.experiment_dir)));
        fprintf(fid, 'raw_dir: %s\n', char(string(logData.raw_dir)));
        fprintf(fid, 'log_dir: %s\n', char(string(logData.log_dir)));
        fprintf(fid, 'save_dir: %s\n', char(string(logData.save_dir)));
        fprintf(fid, 'base_name_requested: %s\n', char(string(logData.base_name_requested)));
        fprintf(fid, 'base_name_resolved: %s\n', char(string(logData.base_name_resolved)));
        fprintf(fid, 'channel_save: %s\n', numericVectorToString(logData.channel_save));
        fprintf(fid, 'save_enabled: %d\n', logical(logData.save_enabled));
        if isfield(logData, 'grab')
            fprintf(fid, 'grab_counter_used: %s\n', num2str(logData.grab.counter_used));
            fprintf(fid, 'grab_files_count: %d\n', numel(logData.grab.files));
            for i = 1:numel(logData.grab.files)
                fprintf(fid, 'grab_file_%02d: %s\n', i, char(string(logData.grab.files{i})));
            end
        end
        if jsonOk
            fprintf(fid, 'json_log: %s\n', jsonPath);
        else
            fprintf(fid, 'json_log: not written\n');
        end
        fclose(fid);
    end

    logInfo = struct();
    logInfo.timestampLocal = tsHuman;
    logInfo.textPath = txtPath;
    if jsonOk
        logInfo.jsonPath = jsonPath;
    else
        logInfo.jsonPath = '';
    end
end

function v = getFieldOr(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName)
        v = s.(fieldName);
    else
        v = defaultValue;
    end
end

function s = numericVectorToString(v)
    if isempty(v)
        s = '';
        return;
    end
    if ~isnumeric(v)
        s = char(string(v));
        return;
    end
    vals = arrayfun(@(x)sprintf('%g', x), v(:)', 'UniformOutput', false);
    s = strjoin(vals, ',');
end

function md = normalizeUserMetadata(userMeta)
    if isstruct(userMeta)
        md = userMeta;
    else
        md = struct('user_metadata', char(string(userMeta)));
    end
end

function out = mergeMetadata(a, b)
    out = a;
    if isempty(b)
        return;
    end
    fn = fieldnames(b);
    for i = 1:numel(fn)
        out.(fn{i}) = b.(fn{i});
    end
end
