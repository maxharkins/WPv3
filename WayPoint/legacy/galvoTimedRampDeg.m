function galvoTimedRampDeg(hX, thetaTarget_deg, T_sec, Fs_Hz, varargin)
% Drive X galvo from current angle to thetaTarget_deg in exactly T_sec using your own AO task.
% Works without feedback calibration and without ALS/Focus/Grab/Loop.

p = inputParser;
p.addParameter('StartDelay_s', 0.002, @(x)isnumeric(x)&&x>=0);
p.addParameter('EndHold_s',   0.002, @(x)isnumeric(x)&&x>=0);
p.addParameter('ParkWhenDone', true,  @(x)islogical(x)||ismember(x,[0 1]));
p.parse(varargin{:});
tLead = p.Results.StartDelay_s; tTail = p.Results.EndHold_s; doPark = logical(p.Results.ParkWhenDone);

assert(T_sec>0 && Fs_Hz>0,'T_sec and Fs_Hz must be > 0');

% Read start and map to volts
theta0 = hX.readPositionOutput();                 % deg (commanded)
V0 = hX.position2Volts(theta0);
V1 = hX.position2Volts(thetaTarget_deg);

% Build [lead hold] -> linear ramp -> [tail hold]
nLead = round(tLead*Fs_Hz);
nRamp = max(1, round(T_sec*Fs_Hz));
nTail = round(tTail*Fs_Hz);
buf = [repmat(V0,nLead,1); linspace(V0,V1,nRamp).'; repmat(V1,nTail,1)];

% Get actual AO endpoint bound to this galvo
dev = hX.hAOControl.deviceName;    % e.g. 'Dev1'
chan = hX.hAOControl.channelID;    % e.g. 0 (AO0)

% Ensure SI is idle, then release the device and play buffer
hX.deinit();                        % cleanly releases AO reservation

import dabs.ni.daqmx.*
t = Task('XAO_Ramp');
t.createAOVoltageChan(dev, chan);
t.cfgSampClkTiming(Fs_Hz, 'DAQmx_Val_FiniteSamps', numel(buf));
t.writeAnalogData(buf, 1, true);    % autoStart
t.waitUntilTaskDone;
t.stop; t.clear;

% Hand control back to ScanImage
hX.reinit();                        % re-acquires and rebuilds tasks
if doPark, hX.park(); end
end
