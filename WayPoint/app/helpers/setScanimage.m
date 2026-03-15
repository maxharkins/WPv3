function setScanimage(workspaceName)
%SETSCANIMAGE Configure MATLAB paths for ScanImage + WPv3 development.
%
% This is an environment bootstrap function that switches MATLAB between:
%   1) The stock ScanImage install ("original")
%   2) The local WPv3 development environment ("harkins")
%
% Place and maintain this function in WPv3 (control layer), not inside the
% ScanImage installation, so environment policy is version-controlled with
% the project.
%
% Usage:
%   setScanimage()               % Defaults to "original"
%   setScanimage("original")
%   setScanimage("harkins")

if nargin < 1
    workspaceName = "original";
end

% Canonical roots for each environment.
scanImageRoot = "C:\Program Files\Vidrio\SI-Premium_2023.0.0_(2023-08-31)_30d238cd06";
maxDocsRoot   = "C:\Users\SCIENTIFICA\Documents\MaxHarkins";
labBoxRoot    = "C:\Users\SCIENTIFICA\Box\Zhang&Brown";
wpv3Root      = "C:\Users\SCIENTIFICA\Documents\MaxHarkins\WPv3";

% Suppress expected warnings when removing paths that are not currently set.
warning('off', 'MATLAB:rmpath:DirNotFound');
cleanupObj = onCleanup(@() warning('on', 'MATLAB:rmpath:DirNotFound')); %#ok<NASGU>

switch lower(string(workspaceName))
    case "original"
        % Use the installed ScanImage as the active MATLAB cwd/context.
        cd(scanImageRoot);

        % Remove local development roots so stock behavior is not shadowed.
        rmpath(genpath(maxDocsRoot));
        rmpath(genpath(labBoxRoot));

    case "harkins"
        % Use the WPv3 repo as the active cwd/context.
        cd(wpv3Root);

        % Add local code + shared lab utilities into the MATLAB path.
        addpath(genpath(maxDocsRoot));
        addpath(genpath(labBoxRoot));

        % Remove ScanImage install tree from path to avoid function conflicts.
        rmpath(genpath(scanImageRoot));

    otherwise
        error('setScanimage:InvalidWorkspace', ...
            'Unknown workspace "%s". Use "original" or "harkins".', workspaceName);
end

end
