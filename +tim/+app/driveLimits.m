function L = driveLimits(cfg, kind)
%DRIVELIMITS The safety criteria of the drive and the largest level each allows.
%
%   L = tim.app.driveLimits(cfg)          % a sine or a sweep
%   L = tim.app.driveLimits(cfg, kind)    % kind 'sweep' | 'stepped' | 'noise'
%
%   Every criterion as the largest PROGRAMMED generator level it allows
%   [Vpp, at generator.load] and the loudspeaker peak voltage that level
%   gives (tim.app.driveEstimate; WO-004, owner decisions 2026-10-12):
%     'speaker'    the loudspeaker test limit loudspeaker.maxPower_W at the
%                  nominal impedance (needs the amplifier gain)
%     'generator'  the safety limit generator.maxVpp, an open-circuit voltage
%     'output'     the largest level of the generator at the load
%                  (capabilities().source of generator.driver)
%   L.criteria    struct array: key, text, maxVpp, maxSpeakerVpk
%   L.maxVpp      the largest programmed level [Vpp] (smallest of the criteria)
%   L.maxSpeakerVpk   the loudspeaker peak voltage at L.maxVpp (NaN without a gain)
%   L.binding     key of the criterion that sets L.maxVpp
%   L.minVpp      the smallest programmed level of the generator at the load
%                 (NaN for an unknown driver)
%   L.limitAboveRated  the test limit exceeds loudspeaker.ratedPower_W
%   The level field of the window and the excitation confirmation use it;
%   the session refuses a level above the loudspeaker test limit
%   (tim:session:speakerPower) and the driver one above maxVpp
%   (tim:gen:amplitude).

if nargin < 2 || isempty(kind), kind = 'sweep'; end
d = tim.app.driveEstimate(cfg, 1, kind);       % per programmed Vpp (linear)
k = d.Vspk_pk;                                 % loudspeaker Vpk per programmed Vpp
ocPerVpp = d.Voc_pp;                           % open-circuit Vpp per programmed Vpp
crit = struct('key', {}, 'text', {}, 'maxVpp', {}, 'maxSpeakerVpk', {});
% loudspeaker: P = (Vpk / crest)^2 / Z <= maxPower_W
spkVpk = sqrt(d.limit_W * d.Z) * d.crest;
crit(end+1) = struct('key', 'speaker', 'text', sprintf('the loudspeaker test limit (%s at %g Ω)', ...
    wattText(d.limit_W), d.Z), 'maxVpp', spkVpk / k, 'maxSpeakerVpk', spkVpk);
% the safety limit generator.maxVpp (open circuit)
v = cfg.generator.maxVpp / ocPerVpp;
crit(end+1) = struct('key', 'generator', 'text', sprintf('generator.maxVpp (%g Vpp open circuit)', ...
    cfg.generator.maxVpp), 'maxVpp', v, 'maxSpeakerVpk', v * k);
% the generator's own range at the load
[lo, hi] = sourceRange(cfg, d.load);
if isfinite(hi)
    crit(end+1) = struct('key', 'output', 'text', sprintf('the largest level of the generator at load %s (%.3g Vpp)', ...
        loadText(d.load), hi), 'maxVpp', hi, 'maxSpeakerVpk', hi * k);
end
m = [crit.maxVpp]; m(isnan(m)) = Inf;
[mx, i] = min(m);
L = struct('criteria', crit, 'maxVpp', mx, 'maxSpeakerVpk', mx * k, 'binding', crit(i).key, ...
    'minVpp', lo, 'limitAboveRated', isfinite(d.rated_W) && d.limit_W > d.rated_W);
end

function [lo, hi] = sourceRange(cfg, load)
% level range of the generator driver at the load; NaN for an unknown driver
lo = NaN; hi = NaN;
name = char(string(cfg.generator.driver));
if ~any(strcmp(name, {tim.instr.drivers().name})), return; end
c = tim.instr.driverInfo(name).capabilities;
if ~isfield(c, 'source'), return; end
[lo, hi] = tim.instr.SignalSource.levelRange(c.source, load);
end

function t = loadText(load)
if strcmp(load, 'INF'), t = 'High Z'; else, t = [load ' Ω']; end
end

function t = wattText(w)
if w >= 1, t = sprintf('%.3g W', w); else, t = sprintf('%.3g mW', 1e3 * w); end
end
