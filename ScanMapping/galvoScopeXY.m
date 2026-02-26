function galvoScopeXY(Fs, chunkSize, totalSeconds)
    % Live plot of X/Y galvo feedback (raw volts) from Dev2/AI10 and Dev2/AI11.
    % Fs: samples/second (e.g., 20000). chunkSize: e.g., 2000. totalSeconds: e.g., 10.
    
    import dabs.ni.daqmx.*
    if nargin < 1, Fs = 20000; end
    if nargin < 2, chunkSize = 2000; end
    if nargin < 3, totalSeconds = inf; end
    
    % Build AI task
    tAI = Task(sprintf('GalvoScope_%d', randi(1e6)));
    cleanupObj = onCleanup(@() tAI.stop());
    
    % X feedback on Dev2/AI10, Y feedback on Dev2/AI11
    tAI.createAIVoltageChan('Dev2', 10, -10, 10);
    tAI.createAIVoltageChan('Dev2', 11, -10, 10);
    tAI.cfgSampClkTiming(Fs, 'DAQmx_Val_ContSamps', chunkSize);
    
    % Prep plotting
    maxPoints = 10*Fs;          % keep ~10 s on screen
    bufX = []; bufY = [];
    hFig = figure('Name','Galvo Feedback (raw V)','Color','w'); 
    hAx  = axes('Parent',hFig); 
    hLx = plot(hAx, nan, nan, '-'); hold(hAx,'on');
    hLy = plot(hAx, nan, nan, '-.');
    xlabel(hAx,'samples'); ylabel(hAx,'volts'); legend(hAx,{'X fb','Y fb'});
    
    tAI.start();
    tStart = tic;
    while ishandle(hFig) && (toc(tStart) < totalSeconds)
        % Read next chunk [N x 2] (columns: X, Y)
        data = tAI.readAnalogData(chunkSize, 'scaled', 2);
        bufX = [bufX; data(:,1)]; %#ok<AGROW>
        bufY = [bufY; data(:,2)]; %#ok<AGROW>
        if numel(bufX) > maxPoints
            bufX = bufX(end-maxPoints+1:end);
            bufY = bufY(end-maxPoints+1:end);
        end
        set(hLx, 'XData', 1:numel(bufX), 'YData', bufX);
        set(hLy, 'XData', 1:numel(bufY), 'YData', bufY);
        drawnow limitrate;
    end
end
