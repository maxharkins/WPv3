function ctx = wpEnsureDailyExperimentFolder(varargin)
%WPENSUREDAILYEXPERIMENTFOLDER Create/reuse today's experiment folder tree.
% Returns resolved directories for:
%   Experiments/YYYY/YYYY-MM-DD_experiment-name/{log,figures,metadata,processed,raw,calibration}

    p = inputParser;
    p.addParameter('DateTime', datetime('now'), @(x) isa(x, 'datetime') && isscalar(x));
    p.addParameter('Create', true, @(x) islogical(x) && isscalar(x));
    p.parse(varargin{:});

    ts = p.Results.DateTime;
    doCreate = p.Results.Create;

    rootDir = resolveExperimentsRoot(doCreate);
    if isempty(rootDir)
        error('Could not resolve Experiments root directory.');
    end

    yearStr = datestr(ts, 'yyyy');
    dayStr = datestr(ts, 'yyyy-mm-dd');

    yearDir = fullfile(rootDir, yearStr);
    if doCreate && ~isfolder(yearDir)
        mkdir(yearDir);
    end

    dayPrefix = [dayStr '_'];
    dayDir = findExistingDayFolder(yearDir, dayPrefix);
    if isempty(dayDir)
        dayDir = fullfile(yearDir, [dayStr '_experiment-name']);
    end
    if doCreate && ~isfolder(dayDir)
        mkdir(dayDir);
    end

    subNames = {'log','figures','metadata','processed','raw','calibration'};
    subdirs = struct();
    for k = 1:numel(subNames)
        nm = subNames{k};
        subPath = fullfile(dayDir, nm);
        subdirs.(nm) = subPath;
        if doCreate && ~isfolder(subPath)
            mkdir(subPath);
        end
    end

    ctx = struct();
    ctx.rootDir = rootDir;
    ctx.yearDir = yearDir;
    ctx.dayDir = dayDir;
    [~, dayName] = fileparts(dayDir);
    ctx.dayFolderName = string(dayName);
    ctx.subdirs = subdirs;
end

function dayDir = findExistingDayFolder(yearDir, dayPrefix)
    dayDir = '';
    if ~isfolder(yearDir)
        return;
    end

    d = dir(fullfile(yearDir, [dayPrefix '*']));
    d = d([d.isdir]);
    if isempty(d)
        return;
    end

    % Prefer explicit placeholder if present; otherwise newest modified.
    exactIdx = find(strcmp({d.name}, [dayPrefix 'experiment-name']), 1, 'first');
    if ~isempty(exactIdx)
        dayDir = fullfile(yearDir, d(exactIdx).name);
        return;
    end

    [~, idx] = max([d.datenum]);
    dayDir = fullfile(yearDir, d(idx).name);
end

function rootDir = resolveExperimentsRoot(doCreate)
    rootDir = '';
    zhangBrownDir = wpFindZhangBrownFolder('StartDir', pwd);
    if isempty(zhangBrownDir)
        return;
    end

    candidate = fullfile(zhangBrownDir, 'Experiments');
    if isfolder(candidate)
        rootDir = candidate;
        return;
    end

    if doCreate
        mkdir(candidate);
        rootDir = candidate;
    end
end
