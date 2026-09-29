function dir_ = getRawExperimentDir()

    % --- 1. Fixed base path ---
    rootPath = fullfile('C:', 'Users', 'SCIENTIFICA', 'Box', 'Zhang&Brown', 'Experiments');

    % --- 2. Date ---
    t = datetime('now');
    yearStr = datestr(t, 'yyyy');
    dateStr = datestr(t, 'yyyy-mm-dd');

    yearDir = fullfile(rootPath, yearStr);

    if ~isfolder(yearDir)
        error('Year folder does not exist: %s', yearDir);
    end

    % --- 3. Find today's experiment folder ---
    pattern = [dateStr, '_*'];
    d = dir(fullfile(yearDir, pattern));
    d = d([d.isdir]);

    if isempty(d)
        error('No experiment folder found for today (%s).', dateStr);
    elseif numel(d) > 1
        names = {d.name};
        error('Multiple experiment folders found for today:\n%s', strjoin(names, '\n'));
    end

    % --- 4. Return raw directory ---
    dir_ = fullfile(yearDir, d(1).name);

end