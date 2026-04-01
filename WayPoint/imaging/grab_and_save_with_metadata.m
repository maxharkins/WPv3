function out = grab_and_save_with_metadata(varargin)
% grab_and_save_with_metadata
% Trigger one ScanImage GRAB and patch TIFF metadata for the files created
% by this acquisition.
%
% This function does NOT move z or control any stage trajectory.
% It only handles imaging capture + file metadata update.
%
% Requires:
% - ScanImage Save enabled (hSI.hChannels.loggingEnable = true)
% - log path + base name already configured (e.g., with configure_grab_basename)
%
% Usage:
%   out = grab_and_save_with_metadata();
%   out = grab_and_save_with_metadata('Config', cfg);
%   out = grab_and_save_with_metadata('Metadata', struct('ablation_pdt_s', 3e-6));
%
% Name-value options:
%   'HSI'       : ScanImage handle (default: evalin('base','hSI'))
%   'Config'    : struct from configure_grab_basename (default: [])
%   'Metadata'  : extra metadata you provide (default: struct())
%   'TimeoutSec': timeout waiting for idle before/after grab (default: 120)
%
% Returns:
%   out struct with fields:
%   files, counterUsed, saveDir, fileStem, metadata

    ip = inputParser();
    ip.addParameter('HSI', [], @(x)isempty(x) || isobject(x));
    ip.addParameter('Config', [], @(x)isempty(x) || isstruct(x));
    ip.addParameter('Metadata', struct(), @(x)isstruct(x) || ischar(x) || (isstring(x) && isscalar(x)));
    ip.addParameter('TimeoutSec', 120, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    ip.parse(varargin{:});

    hSI = ip.Results.HSI;
    cfg = ip.Results.Config;
    userMeta = ip.Results.Metadata;
    timeoutSec = double(ip.Results.TimeoutSec);

    if isempty(hSI)
        if ~evalin('base', "exist('hSI','var')")
            error('grab_and_save_with_metadata:hSIMissing', ...
                'hSI was not found in base workspace. Start ScanImage first.');
        end
        hSI = evalin('base', 'hSI');
    end
    assert(isvalid(hSI), 'grab_and_save_with_metadata:InvalidHSI', 'hSI handle is invalid.');

    if ~hSI.hChannels.loggingEnable
        error('grab_and_save_with_metadata:SaveDisabled', ...
            'ScanImage Save is disabled. Enable Save first.');
    end

    saveDir = hSI.hScan2D.logFilePath;
    stem = hSI.hScan2D.logFileStem;
    if isempty(saveDir) || isempty(stem)
        error('grab_and_save_with_metadata:MissingLogConfig', ...
            'logFilePath/logFileStem is empty. Configure basename first.');
    end

    waitForIdle(hSI, timeoutSec, 'before startGrab');
    counterUsed = hSI.hScan2D.logFileCounter;
    tStart = now;

    hSI.startGrab();
    waitForIdle(hSI, timeoutSec, 'after startGrab');

    files = discoverAcqFiles(saveDir, stem, counterUsed, tStart);
    if isempty(files)
        error('grab_and_save_with_metadata:NoSavedFiles', ...
            'No TIFF file found for this grab (counter %d).', counterUsed);
    end

    foundMeta = collectFoundMetadata(hSI);
    foundMeta.counter_used = counterUsed;
    foundMeta.capture_local = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

    meta = struct();
    if isstruct(cfg) && isfield(cfg, 'metadata') && isstruct(cfg.metadata)
        meta = mergeMetadata(meta, cfg.metadata);
    end
    meta = mergeMetadata(meta, normalizeUserMetadata(userMeta));
    meta = mergeMetadata(meta, foundMeta);

    for i = 1:numel(files)
        patchTiffMetadata(files{i}, meta);
    end

    out = struct();
    out.files = files;
    out.counterUsed = counterUsed;
    out.saveDir = saveDir;
    out.fileStem = stem;
    out.metadata = meta;
end

function waitForIdle(hSI, timeoutSec, phase)
    t = tic;
    while ~strcmpi(hSI.acqState, 'idle')
        if toc(t) > timeoutSec
            error('grab_and_save_with_metadata:IdleTimeout', ...
                'Timed out waiting for idle %s. Current acqState: %s', phase, hSI.acqState);
        end
        pause(0.02);
    end
end

function files = discoverAcqFiles(saveDir, stem, counter, tStart)
    pat = sprintf('%s_%05u*', stem, counter);
    d = dir(fullfile(saveDir, pat));

    if isempty(d)
        % fallback: files created after tStart with this stem
        d = dir(fullfile(saveDir, [stem '*']));
        if ~isempty(d)
            isNew = [d.datenum] >= (tStart - 1e-7);
            d = d(isNew);
        end
    end

    if isempty(d)
        files = {};
        return;
    end

    names = {d.name};
    isDir = [d.isdir];
    isTif = endsWith(lower(names), '.tif') | endsWith(lower(names), '.tiff');
    d = d((~isDir) & isTif);

    if isempty(d)
        files = {};
        return;
    end

    [~, idx] = sort({d.name});
    d = d(idx);
    files = fullfile({d.folder}, {d.name});
end

function md = collectFoundMetadata(hSI)
    md = struct();
    md.zoom_factor = getZoomFactor(hSI);
    md.imaging_pdt_s = getImagingPdt(hSI);
    md.z_um = getCurrentDepthUm(hSI); % required depth metadata
    md.log_file_path = hSI.hScan2D.logFilePath;
    md.log_file_stem = hSI.hScan2D.logFileStem;
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

function patchTiffMetadata(filePath, metadata)
    payload = jsonencode(metadata);
    marker = 'CustomMetadataJSON:';

    t = Tiff(filePath, 'r+');
    c = onCleanup(@()safeCloseTiff(t));

    done = false;
    while ~done
        oldDesc = '';
        try
            oldDesc = t.getTag('ImageDescription');
        catch
        end

        newDesc = upsertMetadataBlob(oldDesc, marker, payload);
        t.setTag('ImageDescription', newDesc);
        t.rewriteDirectory();

        done = t.lastDirectory();
        if ~done
            t.nextDirectory();
        end
    end

    clear c;
    t.close();
end

function desc = upsertMetadataBlob(oldDesc, marker, payload)
    if isempty(oldDesc)
        oldDesc = '';
    end

    oldDesc = char(string(oldDesc));
    idx = strfind(oldDesc, marker);
    if isempty(idx)
        if isempty(oldDesc)
            desc = [marker payload];
        else
            desc = sprintf('%s\n%s%s', oldDesc, marker, payload);
        end
    else
        desc = oldDesc(1:idx(1)-1);
        if ~isempty(desc) && desc(end) == newline
            desc = desc(1:end-1);
        end
        if isempty(desc)
            desc = [marker payload];
        else
            desc = sprintf('%s\n%s%s', desc, marker, payload);
        end
    end
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

function safeCloseTiff(t)
    try
        t.close();
    catch
    end
end
