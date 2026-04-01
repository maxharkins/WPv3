function info = grab_and_save_with_metadata(saveDir, varargin)
% grab_and_save_with_metadata
% Start one ScanImage GRAB and save output TIFF(s) to a designated folder.
% Uses ScanImage's native logging (Save must already be enabled).
% The filename stem includes metadata:
%   - PDT (pixel dwell time, seconds)
%   - depth z (um)
%
% Usage:
%   info = grab_and_save_with_metadata('/path/to/output');
%   info = grab_and_save_with_metadata('/path/to/output', 'Prefix', 'exp1');
%
% Name-value options:
%   'Prefix'     : filename prefix (default: 'grab')
%   'TimeoutSec' : timeout waiting for idle state (default: 120)
%   'HSI'        : ScanImage handle (default: evalin('base','hSI'))
%
% Returns:
%   info struct with fields:
%     saveDir, prefix, pdtSec, zUm, fileStem, expectedCounter, files

    p = inputParser();
    p.addRequired('saveDir', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    p.addParameter('Prefix', 'grab', @(x)ischar(x) || (isstring(x) && isscalar(x)));
    p.addParameter('TimeoutSec', 120, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    p.addParameter('HSI', [], @(x)isempty(x) || isobject(x));
    p.parse(saveDir, varargin{:});

    saveDir = char(string(p.Results.saveDir));
    prefix = char(string(p.Results.Prefix));
    timeoutSec = p.Results.TimeoutSec;
    hSI = p.Results.HSI;

    if isempty(hSI)
        if ~evalin('base', "exist('hSI','var')")
            error('grab_and_save_with_metadata:hSIMissing', ...
                'hSI was not found in base workspace. Start ScanImage first.');
        end
        hSI = evalin('base', 'hSI');
    end

    assert(isvalid(hSI), 'grab_and_save_with_metadata:InvalidHSI', 'hSI handle is invalid.');

    if ~exist(saveDir, 'dir')
        mkdir(saveDir);
    end

    waitForIdle(hSI, timeoutSec, 'before startGrab');

    pdtSec = getPdtSec(hSI);
    zUm = getDepthUm(hSI);
    timeTag = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));

    pdtTok = numToToken(pdtSec, 9);
    zTok = numToToken(zUm, 3);
    stem = sprintf('%s_PDTs%s_Zum%s_%s', prefix, pdtTok, zTok, timeTag);

    if ~hSI.hChannels.loggingEnable
        error('grab_and_save_with_metadata:SaveDisabled', ...
            'ScanImage Save is disabled (hSI.hChannels.loggingEnable=false). Enable Save and try again.');
    end

    % Cache current logging path/stem so this function is side-effect safe.
    oldLogPath = hSI.hScan2D.logFilePath;
    oldLogStem = hSI.hScan2D.logFileStem;

    c = onCleanup(@()restoreLogging(hSI, oldLogPath, oldLogStem));

    hSI.hScan2D.logFilePath = saveDir;
    hSI.hScan2D.logFileStem = stem;
    expectedCounter = hSI.hScan2D.logFileCounter;
    hSI.startGrab();
    waitForIdle(hSI, timeoutSec, 'after startGrab');

    files = discoverSavedFiles(saveDir, stem, expectedCounter);

    info = struct();
    info.saveDir = saveDir;
    info.prefix = prefix;
    info.pdtSec = pdtSec;
    info.zUm = zUm;
    info.fileStem = stem;
    info.expectedCounter = expectedCounter;
    info.files = files;

    clear c;
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

function pdtSec = getPdtSec(hSI)
    pdtSec = NaN;
    try
        pdtSec = double(hSI.hScan2D.scanPixelTimeMean);
    catch
    end

    if ~isfinite(pdtSec)
        try
            pdtSec = double(hSI.hScan2D.pixelBinFactor) / double(hSI.hScan2D.sampleRate);
        catch
            pdtSec = NaN;
        end
    end
end

function zUm = getDepthUm(hSI)
    zUm = NaN;

    % Preferred: current motor/sample z position.
    try
        pos = hSI.hMotors.samplePosition;
        if ~isempty(pos) && numel(pos) >= 3 && isfinite(pos(3))
            zUm = double(pos(3));
            return;
        end
    catch
    end

    % Fallback: first configured stack z.
    try
        zs = hSI.hStackManager.zs;
        if ~isempty(zs) && isfinite(zs(1))
            zUm = double(zs(1));
        end
    catch
    end
end

function tok = numToToken(v, decimals)
    if ~isfinite(v)
        tok = 'NaN';
        return;
    end

    fmt = sprintf('%%.%df', decimals);
    tok = sprintf(fmt, v);
    tok = regexprep(tok, '0+$', '');
    tok = regexprep(tok, '\.$', '');
    tok = strrep(tok, '-', 'm');
    tok = strrep(tok, '.', 'p');
end

function restoreLogging(hSI, oldPath, oldStem)
    try
        hSI.hScan2D.logFilePath = oldPath;
        hSI.hScan2D.logFileStem = oldStem;
    catch
        % best effort restore
    end
end

function files = discoverSavedFiles(saveDir, stem, counter)
    patCounter = sprintf('%s_%05u*', stem, counter);
    d = dir(fullfile(saveDir, patCounter));

    if isempty(d)
        patStem = sprintf('%s*', stem);
        d = dir(fullfile(saveDir, patStem));
    end

    d = d(~[d.isdir]);
    d = d(~endsWith({d.name}, '.meta.txt', 'IgnoreCase', true));

    if isempty(d)
        files = {};
        return;
    end

    [~, idx] = sort([d.datenum], 'descend');
    d = d(idx);
    files = fullfile({d.folder}, {d.name});
end
