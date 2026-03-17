function [stats, model] = playParametricMicronPath(hX, hY, x_in, y_in, PDT_s, varargin)
    % Play a parametric XY path given in microns at constant tangential velocity.
    % The path is resampled to BeamWaistDiameter_um/2 per sample and played at Fs=1/PDT_s.
    %
    % Inputs
    %   hX, hY   : galvo handles (e.g., hSI.hResourceStore.hResources{120/121})
    %   x_in,y_in:
    %       - numeric vectors of waypoints in µm (same length), OR
    %       - function handles @(t)->x_um, @(t)->y_um with t in [0,1]
    %   PDT_s    : pixel dwell time [s] (time per sample)
    %
    % Name/Value options
    %   'BeamWaistDiameter_um' : beam waist diameter in µm (default [])
    %   'Dot_um'               : legacy alias for BeamWaistDiameter_um (default 0.80 µm)
    %   'Model'         : calibration model for micronsToDegrees (default [])
    %   'Tspan'         : [t0 t1] if x_in/y_in are function handles (default [0 1])
    %   'Oversample'    : integer samples used before arc-length resample (default 5000)
    %   'StartHold_s'   : start settle hold (default 0.002 s)
    %   'EndHold_s'     : end settle hold (default 0.002 s)
    %   'BeamHandle'    : handle to beam object (e.g., hSI.hScan2D.hBeams{1}) (default [])
    %   'PowerFrac'     : beam power fraction during motion (default [])
    %   'ParkWhenDone'  : true/false (default false)
    %
    % Outputs
    %   stats: struct with fields Fs_Hz, N, duration_s, totalLength_um, speed_um_s
    %   model: returned/updated model from micronsToDegrees
    %
    % Requirements
    %   - Coordinates must lie within [-500, +500] µm in both X and Y (asserted).
    %   - X and Y AOs must be on the same NI device (e.g., Dev1: ao0/ao1).
    %
    % Notes
    %   - Keeps galvos initialized (scanner-enable asserted).
    %   - Unreserves AOs under the correct users, plays one 2-ch NI task, then reserves back.
    %   - Constant tangential velocity v = (BeamWaistDiameter_um/2) / PDT_s.
    
    % ---- parse inputs ----
    p = inputParser;
    p.addParameter('BeamWaistDiameter_um', [], @(x) isempty(x) || (isnumeric(x) && x > 0));
    p.addParameter('Dot_um',       0.80,  @(x)isnumeric(x) && x>0);
    p.addParameter('Model',        [],    @(x)true);
    p.addParameter('Tspan',        [0 1], @(x)isnumeric(x) && numel(x)==2);
    p.addParameter('Oversample',   5000,  @(x)isnumeric(x) && x>=100);
    p.addParameter('StartHold_s',  0.002, @(x)isnumeric(x) && x>=0);
    p.addParameter('EndHold_s',    0.002, @(x)isnumeric(x) && x>=0);
    p.addParameter('BeamHandle',   [],    @(x)isempty(x) || isobject(x));
    p.addParameter('PowerFrac',    [],    @(x)isempty(x) || (isscalar(x) && x>=0 && x<=1));
    p.addParameter('ParkWhenDone', false, @(x)islogical(x) || ismember(x,[0 1]));
    p.parse(varargin{:});
    if ~isempty(p.Results.BeamWaistDiameter_um)
        beamWaistDiameter_um = p.Results.BeamWaistDiameter_um;
    else
        beamWaistDiameter_um = p.Results.Dot_um; % legacy alias path
    end
    rasterSpacing_um = wpRasterSpacingFromBeamWaist(beamWaistDiameter_um);
    model    = p.Results.Model;
    tspan    = p.Results.Tspan;
    Nover    = p.Results.Oversample;
    tLead_s  = p.Results.StartHold_s;
    tTail_s  = p.Results.EndHold_s;
    bh       = p.Results.BeamHandle;
    pf       = p.Results.PowerFrac;
    doPark   = logical(p.Results.ParkWhenDone);
    
    assert(PDT_s>0,'PDT_s must be > 0');
    Fs = 1 / PDT_s;
    
    % ---- gather waypoints (µm) ----
    if isa(x_in,'function_handle') && isa(y_in,'function_handle')
        t = linspace(tspan(1), tspan(2), Nover).';
        x_um = x_in(t);
        y_um = y_in(t);
    else
        x_um = x_in(:);
        y_um = y_in(:);
    end
    assert(isvector(x_um) && isvector(y_um) && numel(x_um)==numel(y_um), 'x and y must be same-length vectors or function handles.');
    assert(all(abs(x_um) <= 500 & abs(y_um) <= 500), 'Coordinates must be within ±500 µm.');
    
    % ---- uniform arc-length resample to canonical raster spacing ----
    dx  = diff(x_um); dy = diff(y_um);
    ds  = hypot(dx,dy);
    s   = [0; cumsum(ds)];
    L   = s(end);
    if L == 0
        error('Path length is zero.');
    end
    s_step = rasterSpacing_um;
    s_uniform = (0:s_step:L).';
    % Ensure the last point lands exactly on the end:
    if s_uniform(end) < L, s_uniform(end+1) = L; end
    x_um_u = interp1(s, x_um, s_uniform, 'pchip');
    y_um_u = interp1(s, y_um, s_uniform, 'pchip');
    
    % ---- microns -> degrees (vectorized) ----
    [x_deg, y_deg, model] = micronsToDegrees(x_um_u, y_um_u, model);
    
    % ---- safety vs travelRange ----
    trX = hX.travelRange; trY = hY.travelRange;
    assert(all(x_deg>=trX(1) & x_deg<=trX(2)), 'X degrees exceed travelRange [%g, %g]°', trX(1), trX(2));
    assert(all(y_deg>=trY(1) & y_deg<=trY(2)), 'Y degrees exceed travelRange [%g, %g]°', trY(1), trY(2));
    
    % ---- degrees -> volts (vectorized) ----
    Vx = hX.position2Volts(x_deg(:));
    Vy = hY.position2Volts(y_deg(:));
    
    % ---- build holds ----
    nLead = round(tLead_s*Fs);
    nTail = round(tTail_s*Fs);
    Vx = [repmat(Vx(1), nLead, 1); Vx; repmat(Vx(end), nTail, 1)];
    Vy = [repmat(Vy(1), nLead, 1); Vy; repmat(Vy(end), nTail, 1)];
    N  = numel(Vx);
    assert(numel(Vy)==N,'Internal error: Vx/Vy length mismatch.');
    
    % ---- AO endpoints and device consistency ----
    hAOx = hX.hAOControl; hAOy = hY.hAOControl;
    assert(strcmp(hAOx.deviceName, hAOy.deviceName), 'X and Y must be on same NI device.');
    dev  = hAOx.deviceName;
    chans= [hAOx.channelID hAOy.channelID];
    
    % ---- AO range safety ----
    lohi = hAOx.outputRange_V;
    assert(all(Vx>=lohi(1) & Vx<=lohi(2)) && all(Vy>=lohi(1) & Vy<=lohi(2)), 'Waveform exceeds AO output range [%g, %g] V.', lohi(1), lohi(2));
    
    % ---- keep scanners enabled: do NOT deinit; unreserve→play→reserve ----
    if ~hAOx.isUser(hX), hAOx.registerUser(hX,'Control'); end
    if ~hAOy.isUser(hY), hAOy.registerUser(hY,'Control'); end
    hAOx.unreserve(hX);
    hAOy.unreserve(hY);
    
    % ---- Single two-channel NI task (true parallel) ----
    import dabs.ni.daqmx.*
    Vxy = [Vx Vy];
    tAO = Task(sprintf('XY_Path_%d', randi(1e6)));
    %cleanupTask = onCleanup(@() tAO.stop(), tAO.clear());
    
    tAO.createAOVoltageChan(dev, chans);
    tAO.cfgSampClkTiming(Fs, 'DAQmx_Val_FiniteSamps', N);
    tAO.writeAnalogData(Vxy, 0, false);   % preload
    
    % ---- beam gate on, run, beam off ----
    if ~isempty(bh) && ~isempty(pf), try bh.setPowerFraction(pf); catch, end, end
    tic
    tAO.start();
    tAO.waitUntilTaskDone();

    elapsed_s = toc;
    if ~isempty(bh) && ~isempty(pf), try bh.setPowerFraction(0);  catch, end, end
    
    % clean up
    tAO.stop(); tAO.clear();
    
    % ---- give control back (optionally park) ----
    hAOx.reserve(hX);
    hAOy.reserve(hY);
    if doPark
        try, hX.park(); end
        try, hY.park(); end
    end
    
    % ---- stats ----
    stats = struct();
    stats.Fs_Hz         = Fs;
    stats.N             = N;
    stats.duration_s    = N/Fs;
    stats.elapsed_s     = elapsed_s;
    stats.totalLength_um= L;
    stats.speed_um_s    = rasterSpacing_um / PDT_s;     % constant tangential speed
    stats.rasterSpacing_um = rasterSpacing_um;
    
end
