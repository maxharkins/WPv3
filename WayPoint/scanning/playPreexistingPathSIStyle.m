function [stats, model] = playPreexistingPathSIStyle(hX, hY, x_um, y_um, PDT_s, varargin)
[stats, model] = playPreexistingPathSIStyle( ...
    hX, hY, x_um, y_um, 0.2e-3, ...
    'BeamWaistDiameter_um', 0.80, ...
    'BeamHandle', hSI.hScan2D.hBeams{1}, ...
    'PowerFrac', 0.2, ...
    'BlankSharpTurns', true, ...
    'TurnBlank_s', 0.2e-3, ...
    'LeadIn_s', 0, 'TailOut_s', 0, ...
    'AllowUnsyncedBeam', false);

%PLAYPREEXISTINGPATHSISTYLE SI-style arbitrary path playback (galvo-galvo).
%
% Uses ScanImage mroi classes (GalvoGalvo + StimulusField) to generate AO
% using the same arbitrary-stimulus mechanism ScanImage uses, then plays
% the generated AO through NI-DAQ.
%
% Required:
%   hX,hY   : galvo handles (dabs.resources.devices.LinearScanner)
%   x_um,y_um : same-length XY path vectors [um]
%   PDT_s   : desired output sample period [s]
%
% Name/Value:
%   'BeamWaistDiameter_um' ([]) beam waist diameter [um]
%   'Dot_um'               (0.80) legacy alias for beam waist diameter
%   'RasterSpacing_um'     ([]) explicit spacing override [um]
%   'Model'                ([]) micronsToDegrees model
%   'LeadIn_s'             (0) lead samples at first point (beam OFF)
%   'TailOut_s'            (0) tail samples at last point (beam OFF)
%   'StartHold_s'          ([]) legacy alias for LeadIn_s
%   'EndHold_s'            ([]) legacy alias for TailOut_s
%   'BeamHandle'           ([]) beam object
%   'PowerFrac'            ([]) beam power fraction during exposed path
%   'BlankSharpTurns'      (true) beam-blank around sharp turns
%   'TurnAngle_deg'        (45) threshold for sharp turn blanking
%   'TurnBlank_s'          (0) blank-pad around each sharp turn [s]
%   'AllowUnsyncedBeam'    (false) allow software-timed beam fallback
%   'OptimizeAO'           (false) run scanner-set AO optimizer on XY
%   'ParkWhenDone'         (false) park galvos at end

p = inputParser;
p.addParameter('BeamWaistDiameter_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
p.addParameter('Dot_um', 0.80, @(x) isnumeric(x) && isscalar(x) && x > 0);
p.addParameter('RasterSpacing_um', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
p.addParameter('Model', [], @(x) true);
p.addParameter('LeadIn_s', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('TailOut_s', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('StartHold_s', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
p.addParameter('EndHold_s', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
p.addParameter('BeamHandle', [], @(x) isempty(x) || isobject(x));
p.addParameter('PowerFrac', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0 && x <= 1));
p.addParameter('BlankSharpTurns', true, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('TurnAngle_deg', 45, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 180);
p.addParameter('TurnBlank_s', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
p.addParameter('AllowUnsyncedBeam', false, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('OptimizeAO', false, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('ParkWhenDone', false, @(x) islogical(x) || ismember(x, [0 1]));
p.parse(varargin{:});

assert(exist('scanimage.mroi.scannerset.GalvoGalvo', 'class') == 8, ...
    'ScanImage mroi classes are not on the MATLAB path.');
assert(isvector(x_um) && isvector(y_um) && numel(x_um) == numel(y_um), ...
    'x_um and y_um must be same-length vectors.');
assert(numel(x_um) >= 2, 'Path must contain at least two points.');
assert(all(isfinite(x_um)) && all(isfinite(y_um)), 'x_um/y_um must be finite.');
assert(all(abs(x_um) <= 500 & abs(y_um) <= 500), 'Coordinates must lie within +/-500 um.');
assert(isnumeric(PDT_s) && isscalar(PDT_s) && PDT_s > 0, 'PDT_s must be > 0.');

beamWaist_um = p.Results.Dot_um;
if ~isempty(p.Results.BeamWaistDiameter_um)
    beamWaist_um = p.Results.BeamWaistDiameter_um;
end
if ~isempty(p.Results.RasterSpacing_um)
    spacing_um_target = p.Results.RasterSpacing_um;
else
    spacing_um_target = localRasterSpacingFromBeamWaist(beamWaist_um);
end

model = p.Results.Model;
Fs = 1 / PDT_s;

lead_s = p.Results.LeadIn_s;
tail_s = p.Results.TailOut_s;
if ~isempty(p.Results.StartHold_s), lead_s = p.Results.StartHold_s; end
if ~isempty(p.Results.EndHold_s), tail_s = p.Results.EndHold_s; end
nLead = round(lead_s * Fs);
nTail = round(tail_s * Fs);

bh = p.Results.BeamHandle;
pf = p.Results.PowerFrac;
useBeam = ~isempty(bh) && ~isempty(pf);
doTurnBlank = logical(p.Results.BlankSharpTurns);
turnAngleDeg = p.Results.TurnAngle_deg;
turnPadSamples = round(p.Results.TurnBlank_s * Fs);
allowUnsyncedBeam = logical(p.Results.AllowUnsyncedBeam);
doOptimizeAO = logical(p.Results.OptimizeAO);
doPark = logical(p.Results.ParkWhenDone);

% --- Uniform arc-length sample positions at pixel centers (SI-like sampling) ---
x = x_um(:);
y = y_um(:);
dxy = hypot(diff(x), diff(y));
keep = [true; dxy > 0];
x = x(keep);
y = y(keep);
assert(numel(x) >= 2, 'Path must contain at least two unique points.');

s = [0; cumsum(hypot(diff(x), diff(y)))];
L = s(end);
assert(L > 0, 'Zero-length path.');

nExpose = max(1, ceil(L / spacing_um_target));
spacing_um_eff = L / nExpose;
sExpose = ((0:nExpose-1)' + 0.5) * spacing_um_eff;
xExpose_um = interp1(s, x, sExpose, 'linear');
yExpose_um = interp1(s, y, sExpose, 'linear');

% um -> deg (reference path for scannerset)
[xExpose_deg, yExpose_deg, model] = micronsToDegrees(xExpose_um, yExpose_um, model);
xExpose_deg = xExpose_deg(:);
yExpose_deg = yExpose_deg(:);

% --- Build SI mroi scanner set (same mechanism as arbitrary stimulus generation) ---
gx = scanimage.mroi.scanners.Galvo(hX);
gy = scanimage.mroi.scanners.Galvo(hY);
gx.sampleRateHz = Fs;
gy.sampleRateHz = Fs;
gx.flytoTimeSeconds = 0;
gy.flytoTimeSeconds = 0;
gx.flybackTimeSeconds = 0;
gy.flybackTimeSeconds = 0;

fastBeams = scanimage.mroi.scanners.FastBeam.empty();
beamMode = 'none';
if useBeam
    canUseSyncedAO = isprop(bh, 'hAOControl') && ~isempty(bh.hAOControl) ...
        && strcmp(bh.hAOControl.deviceName, hX.hAOControl.deviceName);
    if canUseSyncedAO
        b = scanimage.mroi.scanners.FastBeam(bh);
        b.beamIdx = 1;
        b.siBeamIdx = 1;
        b.powerFraction = pf;
        b.sampleRateHz = Fs;
        b.flybackBlanking = true;
        b.interlaceDecimation = 1;
        b.interlaceOffset = 0;
        b.linePhase = 0;
        b.beamClockDelay = 0;
        b.beamClockExtend = 0;
        fastBeams = b;
        beamMode = 'synced_ao';
    else
        if ~allowUnsyncedBeam
            error(['BeamHandle/PowerFrac supplied but beam AO is not on the XY device (%s). ' ...
                   'Set AllowUnsyncedBeam=true for software-timed fallback.'], hX.hAOControl.deviceName);
        end
        beamMode = 'software_fallback';
    end
end

ss = scanimage.mroi.scannerset.GalvoGalvo( ...
    'CustomSIStyle', gx, gy, fastBeams, scanimage.mroi.scanners.SlowBeam.empty(), ...
    scanimage.mroi.scanners.FastZ.empty(), 1, PDT_s, true, false, 0);
ss.scannerToRefTransform = eye(3);

duration_s = nExpose / Fs;
stimFcn = @(tt, varargin) localStimPath(tt, xExpose_deg, yExpose_deg, Fs); %#ok<NASGU>
sf = scanimage.mroi.scanfield.fields.StimulusField(stimFcn, {}, duration_s, 1, [0 0], [1 1], 0, []);
if useBeam
    sf.powerFractions = pf;
end

[path_FOV, ~] = ss.scanPathStimulusFOV(sf, 0, 0, 0, false, strcmp(beamMode, 'synced_ao'), inf);
ao = ss.pathFovToAo(path_FOV);
Vx = ao.G(:,1);
Vy = ao.G(:,2);

if doOptimizeAO
    aoG_opt = ss.optimizeAO('G', [Vx Vy], [], Fs);
    Vx = aoG_opt(:,1);
    Vy = aoG_opt(:,2);
end

Vb = [];
if strcmp(beamMode, 'synced_ao')
    Vb = ao.B(:,1);
    exposeMask = true(size(Vb));
    if doTurnBlank && numel(Vb) >= 3
        turnMask = localDetectSharpTurns(xExpose_deg, yExpose_deg, turnAngleDeg);
        if turnPadSamples > 0
            turnMask = conv(double(turnMask), double(true(2*turnPadSamples + 1, 1)), 'same') > 0;
        end
        exposeMask(turnMask) = false;
    end
    if nLead > 0 || nTail > 0
        exposeMask = [false(nLead,1); exposeMask; false(nTail,1)];
    end
end

% Lead/tail hold (beam OFF)
if nLead > 0 || nTail > 0
    Vx = [repmat(Vx(1), nLead, 1); Vx; repmat(Vx(end), nTail, 1)];
    Vy = [repmat(Vy(1), nLead, 1); Vy; repmat(Vy(end), nTail, 1)];
    if strcmp(beamMode, 'synced_ao')
        Vb = [zeros(nLead,1); Vb; zeros(nTail,1)];
    end
end
N = numel(Vx);

if strcmp(beamMode, 'synced_ao') && doTurnBlank
    Vb(~exposeMask) = 0;
end

% Optional position-domain safety check (if inverse conversion is available)
if ismethod(hX, 'volts2Position') && ismethod(hY, 'volts2Position')
    trX = hX.travelRange;
    trY = hY.travelRange;
    x_deg_cmd = hX.volts2Position(Vx);
    y_deg_cmd = hY.volts2Position(Vy);
    assert(all(x_deg_cmd >= trX(1) & x_deg_cmd <= trX(2)), ...
        'X exceeds travelRange [%g,%g] deg', trX(1), trX(2));
    assert(all(y_deg_cmd >= trY(1) & y_deg_cmd <= trY(2)), ...
        'Y exceeds travelRange [%g,%g] deg', trY(1), trY(2));
end

hAOx = hX.hAOControl;
hAOy = hY.hAOControl;
assert(strcmp(hAOx.deviceName, hAOy.deviceName), 'X and Y must share the same NI device.');
dev = hAOx.deviceName;

rx = hAOx.outputRange_V;
ry = hAOy.outputRange_V;
assert(all(Vx >= rx(1) & Vx <= rx(2)), 'X waveform exceeds AO range [%g,%g] V.', rx(1), rx(2));
assert(all(Vy >= ry(1) & Vy <= ry(2)), 'Y waveform exceeds AO range [%g,%g] V.', ry(1), ry(2));

chans = [hAOx.channelID hAOy.channelID];
Vao = [Vx Vy];
hAOList = {hAOx hAOy};
hUserList = {hX hY};

if strcmp(beamMode, 'synced_ao')
    hAOb = bh.hAOControl;
    rb = hAOb.outputRange_V;
    assert(all(Vb >= rb(1) & Vb <= rb(2)), 'Beam waveform exceeds AO range [%g,%g] V.', rb(1), rb(2));
    chans(end+1) = hAOb.channelID; %#ok<AGROW>
    Vao(:,end+1) = Vb; %#ok<AGROW>
    hAOList{end+1} = hAOb; %#ok<AGROW>
    hUserList{end+1} = bh; %#ok<AGROW>
end

% Register + unreserve resources for task ownership
didUnreserve = false(1, numel(hAOList));
cleanupReserve = onCleanup(@() localRestoreReservations(hAOList, hUserList, didUnreserve)); %#ok<NASGU>
for k = 1:numel(hAOList)
    hAO = hAOList{k};
    hUser = hUserList{k};
    if ~hAO.isUser(hUser), hAO.registerUser(hUser, 'Control'); end
end
for k = 1:numel(hAOList)
    hAOList{k}.unreserve(hUserList{k});
    didUnreserve(k) = true;
end

% Finite AO playback
import dabs.ni.daqmx.*
tAO = Task(sprintf('XY_SIStyle_%d', randi(1e6)));
cleanupTask = onCleanup(@() localCleanupTask(tAO)); %#ok<NASGU>
tAO.createAOVoltageChan(dev, chans);
tAO.cfgSampClkTiming(Fs, 'DAQmx_Val_FiniteSamps', N);
tAO.writeAnalogData(Vao, 0, false);

if strcmp(beamMode, 'software_fallback')
    try, bh.setPowerFraction(pf); catch, end %#ok<TRYNC>
end

tic;
tAO.start();
tAO.waitUntilTaskDone();
elapsed_s = toc;

if strcmp(beamMode, 'software_fallback')
    try, bh.setPowerFraction(0); catch, end %#ok<TRYNC>
end

for k = 1:numel(hAOList)
    if didUnreserve(k)
        hAOList{k}.reserve(hUserList{k});
        didUnreserve(k) = false;
    end
end

if doPark
    try, hX.park(); end %#ok<TRYNC>
    try, hY.park(); end %#ok<TRYNC>
end

stats = struct( ...
    'Fs_Hz', Fs, ...
    'N_total', N, ...
    'duration_s', N / Fs, ...
    'elapsed_s', elapsed_s, ...
    'totalLength_um', L, ...
    'spacingTarget_um', spacing_um_target, ...
    'spacingEffective_um', spacing_um_eff, ...
    'speedEffective_um_s', spacing_um_eff / PDT_s, ...
    'beamMode', beamMode, ...
    'turnBlanking', logical(doTurnBlank), ...
    'turnBlankPadSamples', turnPadSamples);
end

function [xx, yy] = localStimPath(tt, x, y, Fs)
    t = tt(:);
    tx = (0:numel(x)-1)' / Fs;
    xx = interp1(tx, x, t, 'linear', 'extrap');
    yy = interp1(tx, y, t, 'linear', 'extrap');
end

function spacing_um = localRasterSpacingFromBeamWaist(beamWaist_um)
    if exist('wpRasterSpacingFromBeamWaist', 'file') == 2
        spacing_um = wpRasterSpacingFromBeamWaist(beamWaist_um);
    else
        spacing_um = beamWaist_um / 2;
    end
    validateattributes(spacing_um, {'numeric'}, {'scalar', 'real', 'positive', 'finite'});
end

function turnMask = localDetectSharpTurns(x, y, turnAngleDeg)
    n = numel(x);
    turnMask = false(n, 1);
    if n < 3
        return;
    end
    v1x = x(2:end-1) - x(1:end-2);
    v1y = y(2:end-1) - y(1:end-2);
    v2x = x(3:end)   - x(2:end-1);
    v2y = y(3:end)   - y(2:end-1);
    n1 = hypot(v1x, v1y);
    n2 = hypot(v2x, v2y);
    good = n1 > 0 & n2 > 0;
    dotp = ones(size(v1x));
    dotp(good) = (v1x(good).*v2x(good) + v1y(good).*v2y(good)) ./ (n1(good).*n2(good));
    dotp = min(max(dotp, -1), 1);
    ang = acosd(dotp);
    turnMask(2:end-1) = ang >= turnAngleDeg;
end

function localRestoreReservations(hAOList, hUserList, didUnreserve)
    for k = 1:numel(hAOList)
        if didUnreserve(k)
            try, hAOList{k}.reserve(hUserList{k}); catch, end %#ok<TRYNC>
        end
    end
end

function localCleanupTask(tTask)
    if isempty(tTask) || ~isvalid(tTask), return; end
    try, tTask.stop();  end %#ok<TRYNC>
    try, tTask.clear(); end %#ok<TRYNC>
end
