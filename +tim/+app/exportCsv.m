function exportCsv(res, folder)
%EXPORTCSV Write results.csv and spectra.csv (one row per frequency).
%   results.csv of a result with res.levels (1.6.0) also holds the level at
%   the specimen front face: incident_dB_SPL and faceVelocity_mm_s (rms); an
%   equalized stepped sine (res.equalizer) also eqVoltage_Vpk (the generator
%   level of the step), eqTarget (in the unit of res.equalizer.unit) and
%   eqReached (within the tolerance). A stepped sine (1.6.0) has the settled
%   check: results.csv settleDrift (the largest excess drift over the ports,
%   a fraction of |H|; NaN not judged) and flag_notSettled, spectra.csv
%   settleDrift<c> per DAQ channel.
a = res.analysis;
f = a.f;
v = a.valid;
T = table(f, 'VariableNames', {'f_Hz'});
T.R_re = real(a.R); T.R_im = imag(a.R); T.R_abs = abs(a.R); T.R_phase_deg = rad2deg(angle(a.R));
T.tau_re = real(a.tau); T.tau_im = imag(a.tau); T.tau_abs = abs(a.tau); T.tau_phase_deg = rad2deg(angle(a.tau));
T.Rterm_abs = abs(a.Rterm);
T.Zt_re = real(a.thin.Zt); T.Zt_im = imag(a.thin.Zt);
T.Zt_norm_re = real(a.thin.Zt_norm); T.Zt_norm_im = imag(a.thin.Zt_norm);
T.velocityMismatch = a.thin.velocityMismatch;
T.TL_fromZt_dB = a.thin.TL_dB;
T.TL_fromTau_dB = a.power.TL_tau_dB;
T.Rpow = a.power.Rpow; T.tauPow = a.power.tauPow; T.alpha = a.power.alpha;
T.cond_up = a.waves.cond1; T.cond_down = a.waves.cond2;
if isfield(res, 'levels') && numel(res.levels.f) == numel(f)
    % level at the specimen front face (1.6.0, WO-006 stage 1; NaN when not
    % available, valid with validR); results of older versions have none
    T.incident_dB_SPL = res.levels.incident_dB_SPL(:);
    T.faceVelocity_mm_s = res.levels.faceVelocity_mm_s(:);
end
if isfield(res, 'equalizer') && isfield(res.equalizer, 'vpp') && numel(res.equalizer.vpp) == numel(f)
    % an equalized stepped sine (1.6.0, WO-006 stage 2): the generator level of
    % every step [Vpk], the target (dB SPL or mm/s, res.equalizer.unit) and
    % whether the step reached it within the tolerance (report only)
    q = res.equalizer;
    T.eqVoltage_Vpk = q.vpp(:) / 2;
    T.eqTarget = repmat(q.target, numel(f), 1);
    T.eqReached = q.reached(:);
end
if isfield(v, 'settleDrift')
    % stepped sine, settled check (1.6.0, owner decision 2026-11-04): the
    % largest excess drift over the ports (limit analysis.settleDriftMax)
    T.settleDrift = v.settleDrift(:);
end
T.measured = v.measured; T.geometryOK = v.geometryOK; T.qualityOK = v.qualityOK;
T.valid = v.valid; T.validR = v.validR; T.validTau = v.validTau; T.validThinZt = v.validThinZt;
T.validated = v.validated;
fl = fieldnames(v.flags);
for i = 1:numel(fl), T.(['flag_' fl{i}]) = v.flags.(fl{i}); end
writetable(T, fullfile(folder, 'results.csv'));

s = res.spectra;
S = table(s.f(:), 'VariableNames', {'f_Hz'});
for c = 1:size(s.H, 2)
    S.(sprintf('H%d_re', c)) = real(res.Hchannel(:, c));
    S.(sprintf('H%d_im', c)) = imag(res.Hchannel(:, c));
    S.(sprintf('coh%d', c)) = s.coherence(:, c);
    S.(sprintf('snr%d_dB', c)) = s.snr_dB(:, c);
end
if isfield(res, 'toneLevels')          % stepped sine: level of every step
    tl = res.toneLevels;
    S.f_observed_Hz = tl.fObserved(:);
    for c = 1:size(tl.spl_dB, 2)
        S.(sprintf('level%d_dB_SPL', c)) = tl.spl_dB(:, c);
        S.(sprintf('noise%d_dB_SPL', c)) = tl.noise_dB(:, c);
    end
end
if isfield(s, 'settleDrift')           % stepped sine: excess drift of the settled check per channel
    for c = 1:size(s.settleDrift, 2)
        S.(sprintf('settleDrift%d', c)) = s.settleDrift(:, c);
    end
end
writetable(S, fullfile(folder, 'spectra.csv'));
end
