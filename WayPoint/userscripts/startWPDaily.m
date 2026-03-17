function ctx = startWPDaily(varargin)
%STARTWPDAILY Bootstrap ScanImage + WayPoint and prepare today's folder tree.
% Usage:
%   startWPDaily
%   startWPDaily("harkins")

    workspaceName = "harkins";
    if nargin >= 1 && ~isempty(varargin{1})
        workspaceName = string(varargin{1});
    end

    setScanimage(workspaceName);

    if evalin('base', 'exist(''hSI'',''var'')') == 0
        scanimage;
    end

    ctx = wpEnsureDailyExperimentFolder('Create', true);
    fprintf('[startWPDaily] Day folder: %s\n', ctx.dayDir);

    WP;
end
