function eq = equalizerSettings(st)
%EQUALIZERSETTINGS Settings of the level equalizer of the stepped sine (1.6.0, WO-006).
%
%   eq = tim.app.equalizerSettings(cfg.excitation.stepped)
%   eq = tim.app.equalizerSettings(struct())      the defaults
%
%   The one place of the defaults: st.equalizer (when present) is merged onto
%   them field by field; a missing or empty value keeps the default. A
%   stepped-sine struct without the field (a configuration file or a script
%   of a version before 1.6.0, a test that builds excitation.stepped in code)
%   therefore gives mode 'off', and the session plays today's stepped sine.
%
%   eq.mode          'off' (default) | 'incidentPressure' | 'faceVelocity' -
%                    the controlled quantity at the specimen front face
%   eq.target        the target: dB SPL of the rms incident wave
%                    (incidentPressure) or mm/s rms (faceVelocity)
%   eq.preLevel_dB   level of the pre-measurement relative to the amplitude
%                    field (excitation.stepped.amplitudeVpp) [dB], < 0
%   eq.tolerance_dB  a step within +/- tolerance_dB of the target is "reached"
%
%   Owner decisions 2026-11-04: feedforward for the stepped sine only; the
%   pre-measurement is the same steps at preLevel_dB = -20 dB; tolerance 1 dB;
%   default controlled quantity the incident pressure; while the equalizer
%   is on the amplitude field is the MAXIMUM of every step.

eq = struct('mode', 'off', 'target', 94, 'preLevel_dB', -20, 'tolerance_dB', 1);
if nargin < 1 || ~isstruct(st) || ~isscalar(st) || ~isfield(st, 'equalizer'), return; end
u = st.equalizer;
if ~isstruct(u) || ~isscalar(u), return; end
for f = reshape(fieldnames(eq), 1, [])
    if ~isfield(u, f{1}) || isempty(u.(f{1})), continue; end
    v = u.(f{1});
    if isstring(v) && isscalar(v), v = char(v); end
    eq.(f{1}) = v;
end
end
