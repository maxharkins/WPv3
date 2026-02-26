function [fileDir] = startMosaicImaging(hWP, StagePath)
    arguments
        hWP
        StagePath
    end

    % tileScan(app, 'StartPosition',[-600 -400], 'EndPosition',[600 400], 'ZoomFactor',6, 'TileOverlap',45, 'zLevels, -5:2.5:5, 'ScanOrder', 'TLRB', 'Snake', true)
    hSI = hWP.hSI;
    hSICtl = hWP.hSICtl;
    % assign this other thing

    
    hSI.hBeams.enablePowerBox = 0; % SET POWERBOXES OFF
    % SET SAVE SCANS ON
    baseDir = 'C:\Users\SCIENTIFICA\Box\Max data and images';
    todaysDir = fullfile(baseDir, string(datetime('today')));
    mkdir(todaysDir)
    fileDir = fullfile(todaysDir, char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-SS')));
    mkdir(fileDir);
    
    hSI.hScan2D.logFilePath = char(fileDir);

    zoomFactor = 10*str2double(hSICtl.hGUIData.mainControlsV4.zoomtens.String)...
        + 1*str2double(hSICtl.hGUIData.mainControlsV4.zoomones.String) ...
        + 0.1*str2double(hSICtl.hGUIData.mainControlsV4.zoomfrac.String);

    zoom = sprintf('%.1f',zoomFactor);                          % SET ZOOM FROM hSI
    laserPower = hSI.hBeams.powers;                             % SET LASER POWER FROM hSI
    PDT = sprintf('%.0f', hSI.hScan2D.scanPixelTimeMean*10^9);  % SET PDT FROM hSI

    fileName = sprintf('PDT%s_Zoom%s', PDT, zoom);   
    %baseDir = 'Images\TileScan';
    %fileDir = fullfile(baseDir, char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-SS')));
    %mkdir(fileDir);

    hSI.hScan2D.logFilePath = char(fileDir);
    hSI.hScan2D.logFileStem = fileName;

    % hSI.hStackManager.enable = 0;                           % SET hSI STACKS OFF
    hSI.acqsPerLoop = size(StagePath, 1);                   % SET hSI NumAcqs = NumStacks;
    hWP.Sequence.CountFrames    = 1;
    hWP.Sequence.CountVolumes   = 0;
    hWP.Sequence.CountStacks    = 0;
    hWP.Sequence.PathIdx = 1;
end