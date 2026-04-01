function cfg = configure_grab_basename(saveDir, baseName, varargin)
% configure_grab_basename
% Configure ScanImage logging directory + basename for upcoming grabs.
%
% If basename already exists in the directory, a numeric suffix is added:
%   basename_0002, basename_0003, ...
%
% This function does NOT trigger acquisition. It only prepares naming.
%
% Usage:
%   cfg = configure_grab_basename('/data/out', 'mouse42', ...
%       'UserMetadata', struct('ablation_pdt_s', 3e-6));
%
% Name-value options:
%   'HSI'            : ScanImage handle (default: evalin('base','hSI'))
%   'UserMetadata'   : struct/string metadata you provide (default: struct())
%   'SuffixDigits'   : suffix width (default: 4)
%
% Returns:
%   cfg struct with fields:
%   saveDir, baseNameRequested, baseNameResolved, metadata

    ip = inputParser();
    ip.addRequired('saveDir', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    ip.addRequired('baseName', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('HSI', [], @(x)isempty(x) || isobject(x));
    ip.addParameter('UserMetadata', struct(), @(x)isstruct(x) || ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('SuffixDigits', 4, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && mod(x,1)==0);
    ip.parse(saveDir, baseName, varargin{:});

    saveDir = char(string(ip.Results.saveDir));
    baseName = char(string(ip.Results.baseName));
    hSI = ip.Results.HSI;
    userMeta = ip.Results.UserMetadata;
    suffixDigits = double(ip.Results.SuffixDigits);

    if isempty(hSI)
        if ~evalin('base', "exist('hSI','var')")
            error('configure_grab_basename:hSIMissing', ...
                'hSI was not found in base workspace. Start ScanImage first.');
        end
        hSI = evalin('base', 'hSI');
    end
    assert(isvalid(hSI), 'configure_grab_basename:InvalidHSI', 'hSI handle is invalid.');

    if ~exist(saveDir, 'dir')
        mkdir(saveDir);
    end

    baseName = sanitizeBaseName(baseName);
    resolvedBase = chooseUniqueBaseName(saveDir, baseName, suffixDigits);

    hSI.hScan2D.logFilePath = saveDir;
    hSI.hScan2D.logFileStem = resolvedBase;

    foundMeta = collectFoundMetadata(hSI);
    metadata = mergeMetadata(foundMeta, normalizeUserMetadata(userMeta));
    metadata.configured_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    cfg = struct();
    cfg.saveDir = saveDir;
    cfg.baseNameRequested = baseName;
    cfg.baseNameResolved = resolvedBase;
    cfg.metadata = metadata;
end

function baseName = sanitizeBaseName(baseName)
    baseName = regexprep(baseName, '\.(tif|tiff)$', '', 'ignorecase');
    baseName = strtrim(baseName);
    baseName = regexprep(baseName, '[/\\\*:\?"<>\|]', '_');
    if isempty(baseName)
        baseName = 'grab';
    end
end

function resolved = chooseUniqueBaseName(saveDir, baseName, digits)
    if ~anyPrefixExists(saveDir, baseName)
        resolved = baseName;
        return;
    end

    for idx = 2:9999
        candidate = sprintf('%s_%0*d', baseName, digits, idx);
        if ~anyPrefixExists(saveDir, candidate)
            resolved = candidate;
            return;
        end
    end

    error('configure_grab_basename:NoUniqueName', ...
        'Unable to resolve unique basename in %s', saveDir);
end

function tf = anyPrefixExists(saveDir, stem)
    d = dir(fullfile(saveDir, [stem '*']));
    tf = any(~[d.isdir]);
end

function md = normalizeUserMetadata(userMeta)
    if isstruct(userMeta)
        md = userMeta;
    else
        md = struct('user_metadata', char(string(userMeta)));
    end
end

function md = collectFoundMetadata(hSI)
    md = struct();
    md.zoom_factor = getZoomFactor(hSI);
    md.imaging_pdt_s = getImagingPdt(hSI);
    md.current_z_um = getCurrentDepthUm(hSI);
    md.log_file_path = hSI.hScan2D.logFilePath;
    md.log_file_stem = hSI.hScan2D.logFileStem;
    md.log_file_counter = hSI.hScan2D.logFileCounter;
    md.save_enabled = logical(hSI.hChannels.loggingEnable);
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
        end
    catch
    end
end

function v = getZoomFactor(hSI)
    v = nan;
    try
        v = double(hSI.hRoiManager.scanZoomFactor);
    catch
    end
end

function pdt = getImagingPdt(hSI)
    pdt = nan;
    try
        pdt = double(hSI.hScan2D.scanPixelTimeMean);
    catch
    end
    if ~isfinite(pdt)
        try
            pdt = double(hSI.hScan2D.pixelBinFactor) / double(hSI.hScan2D.sampleRate);
        catch
            pdt = nan;
        end
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
