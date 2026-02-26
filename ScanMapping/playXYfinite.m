function playXYfinite(hX, hY, Vx, Vy, Fs, varargin)
% Play synchronized finite waveforms on X and Y galvos using their internal players.
% Inputs:
%   hX, hY : galvo handles (e.g., hSI.hResourceStore.hResources{120/121})
%   Vx, Vy : column vectors [N x 1] in volts (same length)
%   Fs     : sample rate [Hz]
% Options (name/value):
%   'BeamHandle'   : handle to beam (e.g., hSI.hScan2D.hBeams{1}) or []
%   'PowerFrac'    : scalar in [0..1] to set during motion (default [])
%   'StartHold_s'  : seconds to hold initial V for settle (default 0.002)
%   'EndHold_s'    : seconds to hold final V for settle (default 0.002)

p = inputParser;
p.addParameter('BeamHandle', [], @(x) isempty(x) || isobject(x));
p.addParameter('PowerFrac', [], @(x) isempty(x) || (isscalar(x) && x>=0 && x<=1));
p.addParameter('StartHold_s', 0.002, @(x)isnumeric(x) && x>=0);
p.addParameter('EndHold_s',   0.002, @(x)isnumeric(x) && x>=0);
p.parse(varargin{:});
bh = p.Results.BeamHandle; pf = p.Results.PowerFrac;
tLead = p.Results.StartHold_s; tTail = p.Results.EndHold_s;

assert(isvector(Vx) && isvector(Vy) && numel(Vx)==numel(Vy), 'Vx/Vy must be same length.');
Vx = Vx(:); Vy = Vy(:);

% Pre/after holds
nLead = round(tLead*Fs); nTail = round(tTail*Fs);
Vx = [repmat(Vx(1), nLead, 1); Vx; repmat(Vx(end), nTail, 1)];
Vy = [repmat(Vy(1), nLead, 1); Vy; repmat(Vy(end), nTail, 1)];

% Optional beam gate
if ~isempty(bh) && ~isempty(pf)
    try, bh.setPowerFraction(pf); catch, end
end

% Start X then Y back-to-back (few-µs skew at most)
hX.testWaveformVolts(Vx, Fs, false, Vx(1));
hY.testWaveformVolts(Vy, Fs, false, Vy(1));

% Wait for both to finish
hX.waitMoveComplete();
hY.waitMoveComplete();

% Beam off
if ~isempty(bh) && ~isempty(pf)
    try, bh.setPowerFraction(0); catch, end
end
end
