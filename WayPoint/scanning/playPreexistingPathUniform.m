function [stats, model] = playPreexistingPathUniform(hX, hY, x_um, y_um, PDT_s, varargin)
%PLAYPREEXISTINGPATHUNIFORM Uniform-dose playback for arbitrary XY paths.
%
% This function is designed to minimize edge over-dose by:
%   1) midpoint arc-length sampling (no endpoint exposure samples),
%   2) optional sharp-turn beam blanking,
%   3) optional sample-synchronous beam AO in the same NI task as XY.
%
% Required:
%   hX,hY   : galvo handles
%   x_um,y_um : same-length path coordinates in microns
%   PDT_s   : sample interval (pixel dwell time), seconds
%
% Name/Value:
%   'BeamWaistDiameter_um' ([]) beam waist diameter [um]
%   'Dot_um'               (0.80) legacy alias for beam waist diameter
%   'RasterSpacing_um'     ([]) explicit spacing override [um]
%   'Model'                ([]) micronsToDegrees calibration model
%   'LeadIn_s'             (0) leading settle time, beam OFF
%   'TailOut_s'            (0) trailing settle time, beam OFF
%   'StartHold_s'          ([]) legacy alias for LeadIn_s (beam OFF)
%   'EndHold_s'            ([]) legacy alias for TailOut_s (beam OFF)
%   'BeamHandle'           ([]) beam object (e.g. hSI.hScan2D.hBeams{1})
%   'PowerFrac'            ([]) nominal beam fraction during exposed samples
%   'BlankSharpTurns'      (true) blank beam around sharp direction changes
%   'TurnAngle_deg'        (45) sharp-turn threshold
%   'TurnBlank_s'          ([]) extra blank pad around detected turns
%   'SpeedPowerComp'       (true) scale beam by local commanded step length
%   'MaxPowerFrac'         (1) clip for compensated beam fraction
%   'AllowUnsyncedBeam'    (false) allow software-timed beam fallback
%   'ParkWhenDone'         (false) park both galvos after playback

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
p.addParameter('PowerFrac', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x >= 0 && x <= 1));
p.addParameter('BlankSharpTurns', true, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('TurnAngle_deg', 45, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 180);
p.addParameter('TurnBlank_s', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
p.addParameter('SpeedPowerComp', true, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('MaxPowerFrac', 1, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
p.addParameter('AllowUnsyncedBeam', false, @(x) islogical(x) || ismember(x, [0 1]));
p.addParameter('ParkWhenDone', false, @(x) islogical(x) || ismember(x, [0 1]));
p.parse(varargin{:});

assert(isvector(x_um) && isvector(y_um) && numel(x_um) == numel(y_um), ...
    'x_um and y_um must be same-length vectors.');
assert(~isempty(x_um), 'x_um/y_um cannot be empty.');
assert(all(isfinite(x_um)) && all(isfinite(y_um)), 'x_um and y_um must be finite.');
assert(all(abs(x_um) <= 500 & abs(y_um) <= 500), 'Coordinates must lie within +/-500 um.');
assert(isnumeric(PDT_s) && isscalar(PDT_s) && PDT_s > 0, 'PDT_s must be > 0.');

% Parse spacing
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

doTurnBlank = logical(p.Results.BlankSharpTurns);
turnAngleDeg = p.Results.TurnAngle_deg;
turnBlank_s = p.Results.TurnBlank_s;
if isempty(turnBlank_s)
    turnPadSamp = 1;
else
    turnPadSamp = round(turnBlank_s * Fs);
end

bh = p.Results.BeamHandle;
pf = p.Results.PowerFrac;
useBeam = ~isempty(bh) && ~isempty(pf);
useSpeedComp = logical(p.Results.SpeedPowerComp);
maxPowerFrac = p.Results.MaxPowerFrac;
allowUnsyncedBeam = logical(p.Results.AllowUnsyncedBeam);
doPark = logical(p.Results.ParkWhenDone);

% Build unique polyline
x = x_um(:);
y = y_um(:);
step = hypot(diff(x), diff(y));
keep = [true; step > 0];
x = x(keep);
y = y(keep);
assert(numel(x) >= 2, 'Path must contain at least two unique points.');

% Arc-length parameterization
s = [0; cumsum(hypot(diff(x), diff(y)))];
L = s(end);
assert(L > 0, 'Zero-length path.');

% Exposure samples: midpoint sampling avoids endpoint over-dose
nExpose = max(1, ceil(L / spacing_um_target));
spacing_um_eff = L / nExpose;
sExpose = ((0:nExpose-1)' + 0.5) * spacing_um_eff;
xExpose = interp1(s, x, sExpose, 'linear');
yExpose = interp1(s, y, sExpose, 'linear');

% Commanded path includes start/end points and optional beam-off settles
sCmd = [zeros(nLead+1, 1); sExpose; repmat(L, nTail+1, 1)];
xCmd_um = interp1(s, x, sCmd, 'linear');
yCmd_um = interp1(s, y, sCmd, 'linear');
N = numel(xCmd_um);

% Exposure mask for commanded samples
exposeMask = false(N, 1);
idxExpose = (nLead+2):(nLead+1+nExpose);
if ~isempty(idxExpose)
    exposeMask(idxExpose) = true;
end

% Blank around sharp turns to avoid reversal over-dose
turnMaskExpose = false(nExpose, 1);
if doTurnBlank && nExpose >= 3
    turnMaskExpose = localDetectSharpTurns(xExpose, yExpose, turnAngleDeg);
    if turnPadSamp > 0
        turnMaskExpose = conv(double(turnMaskExpose), double(true(2*turnPadSamp+1,1)), 'same') > 0;
    end
    exposeMask(idxExpose(turnMaskExpose)) = false;
end

% um -> deg
[x_deg, y_deg, model] = micronsToDegrees(xCmd_um, yCmd_um, model);
x_deg = x_deg(:);
y_deg = y_deg(:);

% Travel range safety
trX = hX.travelRange;
trY = hY.travelRange;
assert(all(x_deg >= trX(1) & x_deg <= trX(2)), ...
    'X exceeds travelRange [%g,%g] deg', trX(1), trX(2));
assert(all(y_deg >= trY(1) & y_deg <= trY(2)), ...
    'Y exceeds travelRange [%g,%g] deg', trY(1), trY(2));

% deg -> volts
Vx = hX.position2Volts(x_deg);
Vy = hY.position2Volts(y_deg);

% AO resources
hAOx = hX.hAOControl;
hAOy = hY.hAOControl;
assert(strcmp(hAOx.deviceName, hAOy.deviceName), 'X and Y must share the same NI device.');
dev = hAOx.deviceName;

% Range safety (XY)
rx = hAOx.outputRange_V;
ry = hAOy.outputRange_V;
assert(all(Vx >= rx(1) & Vx <= rx(2)), 'X waveform exceeds AO range [%g,%g] V.', rx(1), rx(2));
assert(all(Vy >= ry(1) & Vy <= ry(2)), 'Y waveform exceeds AO range [%g,%g] V.', ry(1), ry(2));

% Build AO channel list
chans = [hAOx.channelID hAOy.channelID];
Vao = [Vx Vy];
hAOList = {hAOx hAOy};
hUserList = {hX hY};
beamMode = 'none';
pFracWave = zeros(N,1);

if useBeam
    canUseSyncedAO = false;
    hAOb = [];
    if isprop(bh, 'hAOControl') && ~isempty(bh.hAOControl) && ismethod(bh, 'convertPowerFraction2Volt')
        hAOb = bh.hAOControl;
        canUseSyncedAO = strcmp(hAOb.deviceName, dev);
    end

    if canUseSyncedAO
        beamMode = 'synced_ao';
        pFracWave(exposeMask) = pf;
        if useSpeedComp
            dsLocal = localLocalStepLength(xCmd_um, yCmd_um);
            scale = dsLocal ./ max(spacing_um_eff, eps);
            scale = max(scale, 0);
            pFracWave(exposeMask) = pFracWave(exposeMask) .* scale(exposeMask);
        end
        pFracWave = min(max(pFracWave, 0), maxPowerFrac);
        try
            Vb = bh.convertPowerFraction2Volt(pFracWave);
        catch
            % Some beam classes only accept scalar conversion inputs.
            Vb = arrayfun(@(v) bh.convertPowerFraction2Volt(v), pFracWave);
        end
        Vb = Vb(:);
        rb = hAOb.outputRange_V;
        assert(all(Vb >= rb(1) & Vb <= rb(2)), ...
            'Beam waveform exceeds AO range [%g,%g] V.', rb(1), rb(2));

        chans(end+1) = hAOb.channelID; %#ok<AGROW>
        Vao(:, end+1) = Vb; %#ok<AGROW>
        hAOList{end+1} = hAOb; %#ok<AGROW>
        hUserList{end+1} = bh; %#ok<AGROW>
    else
        if ~allowUnsyncedBeam
            error(['BeamHandle/PowerFrac supplied but synchronized beam AO is unavailable on %s. ' ...
                   'Use AllowUnsyncedBeam=true to permit software-timed fallback.'], dev);
        end
        beamMode = 'software_fallback';
    end
end

% Register + unreserve shared AO resources
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

% Shared finite AO task
import dabs.ni.daqmx.*
tAO = Task(sprintf('XY_Uniform_%d', randi(1e6)));
cleanupTask = onCleanup(@() localCleanupTask(tAO)); %#ok<NASGU>
tAO.createAOVoltageChan(dev, chans);
tAO.cfgSampClkTiming(Fs, 'DAQmx_Val_FiniteSamps', N);
tAO.writeAnalogData(Vao, 0, false);

% Software fallback beam (non-synchronous)
if strcmp(beamMode, 'software_fallback')
    try
        bh.setPowerFraction(pf);
    catch
    end
end

tic;
tAO.start();
tAO.waitUntilTaskDone();
elapsed_s = toc;

if strcmp(beamMode, 'software_fallback')
    try
        bh.setPowerFraction(0);
    catch
    end
end

% Re-reserve resources now that task completed
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
    'N_exposed', nnz(exposeMask), ...
    'duration_s', N / Fs, ...
    'exposedDuration_s', nnz(exposeMask) / Fs, ...
    'elapsed_s', elapsed_s, ...
    'totalLength_um', L, ...
    'spacingTarget_um', spacing_um_target, ...
    'spacingEffective_um', spacing_um_eff, ...
    'speedEffective_um_s', spacing_um_eff / PDT_s, ...
    'turnBlankedSamples', nnz(turnMaskExpose), ...
    'beamMode', beamMode);
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
    good = (n1 > 0) & (n2 > 0);
    dotp = ones(size(v1x));
    dotp(good) = (v1x(good).*v2x(good) + v1y(good).*v2y(good)) ./ (n1(good).*n2(good));
    dotp = min(max(dotp, -1), 1);
    ang = acosd(dotp);

    turnMask(2:end-1) = ang >= turnAngleDeg;
end

function dsLocal = localLocalStepLength(x, y)
    d = [0; hypot(diff(x), diff(y))];
    if numel(d) <= 1
        dsLocal = d;
        return;
    end
    dsLocal = 0.5 * (d + [d(2:end); d(end)]);
end

function localRestoreReservations(hAOList, hUserList, didUnreserve)
    for k = 1:numel(hAOList)
        if didUnreserve(k)
            try
                hAOList{k}.reserve(hUserList{k});
            catch
            end
        end
    end
end

function localCleanupTask(tTask)
    if isempty(tTask) || ~isvalid(tTask), return; end
    try, tTask.stop();  end %#ok<TRYNC>
    try, tTask.clear(); end %#ok<TRYNC>
end
