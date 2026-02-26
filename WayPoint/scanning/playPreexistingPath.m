function [stats, model] = playPreexistingPath(hX, hY, x_um, y_um, PDT_s, varargin)
% Play a pre-existing XY path (µm) at constant tangential velocity.
% Resamples to 0.80 µm spacing and plays at Fs = 1/PDT_s with one 2-ch NI task.
%
% hX,hY : galvo handles (e.g., hSI.hResourceStore.hResources{120/121})
% x_um,y_um : numeric vectors (same length) of path coordinates in microns
% PDT_s : pixel dwell time [s]
%
% Name/Value:
%   'BeamWaistDiameter_um' (0.80) spatial step per sample [µm] (canonical)
%   'Dot_um'               (0.80) legacy alias for BeamWaistDiameter_um
%   'Model'        ([])    micronsToDegrees calibration model (reused/returned)
%   'StartHold_s'  (0.002) seconds to hold initial point
%   'EndHold_s'    (0.002) seconds to hold final point
%   'BeamHandle'   ([])    e.g., hSI.hScan2D.hBeams{1}
%   'PowerFrac'    ([])    0..1 power fraction during motion
%   'ParkWhenDone' (false) park both galvos after playback

p = inputParser;
p.addParameter('BeamWaistDiameter_um', [], @(x)isempty(x) || (isnumeric(x)&&x>0));
p.addParameter('Dot_um',       0.80,  @(x)isnumeric(x)&&x>0);
p.addParameter('Model',        [],    @(x)true);
p.addParameter('StartHold_s',  0.002, @(x)isnumeric(x)&&x>=0);
p.addParameter('EndHold_s',    0.002, @(x)isnumeric(x)&&x>=0);
p.addParameter('BeamHandle',   [],    @(x)isempty(x)||isobject(x));
p.addParameter('PowerFrac',    [],    @(x)isempty(x)||(isscalar(x)&&x>=0&&x<=1));
p.addParameter('ParkWhenDone', false, @(x)islogical(x)||ismember(x,[0 1]));
p.parse(varargin{:});
if ~isempty(p.Results.BeamWaistDiameter_um)
    beamWaistDiameter_um = p.Results.BeamWaistDiameter_um;
else
    beamWaistDiameter_um = p.Results.Dot_um; % legacy alias path
end
model = p.Results.Model;
tLead = p.Results.StartHold_s; tTail = p.Results.EndHold_s;
bh = p.Results.BeamHandle; pf = p.Results.PowerFrac;
doPark = logical(p.Results.ParkWhenDone);

assert(isvector(x_um)&&isvector(y_um)&&numel(x_um)==numel(y_um), 'x_um and y_um must be same-length vectors.');
assert(all(abs(x_um)<=500 & abs(y_um)<=500), 'Coordinates must lie within ±500 µm.');
assert(PDT_s>0,'PDT_s must be > 0');
Fs = 1/PDT_s;

% ---- Uniform arc-length resample to constant 0.80 µm spacing ----
x = x_um(:); y = y_um(:);
dx = diff(x); dy = diff(y);
s = [0; cumsum(hypot(dx,dy))];
L = s(end); assert(L>0,'Zero-length path.');
s_uniform = (0:beamWaistDiameter_um:L).';
if s_uniform(end) < L, s_uniform(end+1) = L; end
x_u = interp1(s,x,s_uniform,'pchip');
y_u = interp1(s,y,s_uniform,'pchip');

% ---- µm -> deg via your calibration (vectorized) ----
[x_deg, y_deg, model] = micronsToDegrees(x_u, y_u, model);

% ---- Travel range safety ----
trX = hX.travelRange; trY = hY.travelRange;
assert(all(x_deg>=trX(1) & x_deg<=trX(2)), 'X exceeds travelRange [%g,%g]°', trX(1), trX(2));
assert(all(y_deg>=trY(1) & y_deg<=trY(2)), 'Y exceeds travelRange [%g,%g]°', trY(1), trY(2));

% ---- deg -> volts ----
Vx = hX.position2Volts(x_deg(:));
Vy = hY.position2Volts(y_deg(:));

% ---- Start/end holds ----
nLead = round(tLead*Fs); nTail = round(tTail*Fs);
Vx = [repmat(Vx(1),nLead,1); Vx; repmat(Vx(end),nTail,1)];
Vy = [repmat(Vy(1),nLead,1); Vy; repmat(Vy(end),nTail,1)];
N = numel(Vx); assert(numel(Vy)==N);

% ---- Shared NI task on Dev1 (both channels) ----
hAOx = hX.hAOControl; hAOy = hY.hAOControl;
assert(strcmp(hAOx.deviceName,hAOy.deviceName),'X and Y must share the same NI device.');
dev = hAOx.deviceName; chans = [hAOx.channelID hAOy.channelID];

% AO range safety
lohi = hAOx.outputRange_V;
assert(all(Vx>=lohi(1)&Vx<=lohi(2)) && all(Vy>=lohi(1)&Vy<=lohi(2)), ...
    'Waveform exceeds AO range [%g,%g] V.', lohi(1), lohi(2));

% Keep scanners enabled: unreserve→play→reserve (no deinit)
if ~hAOx.isUser(hX), hAOx.registerUser(hX,'Control'); end
if ~hAOy.isUser(hY), hAOy.registerUser(hY,'Control'); end
hAOx.unreserve(hX); hAOy.unreserve(hY);

import dabs.ni.daqmx.*
Vxy = [Vx Vy];
tAO = Task(sprintf('XY_Path_%d', randi(1e6)));
cleanupTask = onCleanup(@() cleanupDAQTask(tAO));
tAO.createAOVoltageChan(dev, chans);
tAO.cfgSampClkTiming(Fs,'DAQmx_Val_FiniteSamps',N);
tAO.writeAnalogData(Vxy,0,false);

% Beam on, run, beam off
if ~isempty(bh) && ~isempty(pf), try bh.setPowerFraction(pf); catch, end, end
tic
tAO.start();
tAO.waitUntilTaskDone();
elapsed_s = toc;
if ~isempty(bh) && ~isempty(pf), try bh.setPowerFraction(0); catch, end, end

% Give AO back (optionally park)
hAOx.reserve(hX); hAOy.reserve(hY);
if doPark, try hX.park(); end; try hY.park(); end; end

% Stats
stats = struct('Fs_Hz',Fs, 'N',N, 'duration_s',N/Fs, ...
               'elapsed_s',elapsed_s, ...
               'totalLength_um',L, ...
               'speed_um_s', beamWaistDiameter_um / PDT_s);
end

function cleanupDAQTask(tTask)
    if isempty(tTask) || ~isvalid(tTask), return; end
    try, tTask.stop();  end
    try, tTask.clear(); end
end
