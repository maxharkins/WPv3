function zhangBrownDir = wpFindZhangBrownFolder(varargin)
%WPFINDZHANGBROWNFOLDER Resolve the local Zhang&Brown folder in Box.
% Searches upward from a start directory for a Box* ancestor, then checks
% common macOS/Windows Box locations.

    p = inputParser;
    p.addParameter('StartDir', pwd, @(x) ischar(x) || (isstring(x) && isscalar(x)));
    p.parse(varargin{:});

    startDir = char(string(p.Results.StartDir));
    zhangBrownDir = '';

    boxDir = findBoxAncestor(startDir);
    if ~isempty(boxDir)
        candidate = fullfile(boxDir, 'Zhang&Brown');
        if isfolder(candidate)
            zhangBrownDir = candidate;
            return;
        end
    end

    homeDir = char(java.lang.System.getProperty('user.home'));
    candidates = {
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box-Box', 'Zhang&Brown')
        fullfile(homeDir, 'Library', 'CloudStorage', 'Box', 'Zhang&Brown')
        fullfile(homeDir, 'Box-Box', 'Zhang&Brown')
        fullfile(homeDir, 'Box', 'Zhang&Brown')
    };

    if ispc
        userProfile = getenv('USERPROFILE');
        if ~isempty(userProfile)
            candidates = [candidates; { ...
                fullfile(userProfile, 'Box-Box', 'Zhang&Brown'); ...
                fullfile(userProfile, 'Box', 'Zhang&Brown') ...
            }]; %#ok<AGROW>
        end

        candidates = [candidates; { ...
            fullfile('C:\Users\SCIENTIFICA\Box-Box', 'Zhang&Brown'); ...
            fullfile('C:\Users\SCIENTIFICA\Box', 'Zhang&Brown') ...
        }]; %#ok<AGROW>
    end

    for i = 1:numel(candidates)
        candidate = candidates{i};
        if isfolder(candidate)
            zhangBrownDir = candidate;
            return;
        end
    end
end

function boxDir = findBoxAncestor(startDir)
    boxDir = '';
    cursor = startDir;

    while true
        [parent, name] = fileparts(cursor);
        if startsWith(name, 'Box') && isfolder(cursor)
            boxDir = cursor;
            return;
        end

        if isempty(parent) || strcmp(parent, cursor)
            break;
        end
        cursor = parent;
    end
end
