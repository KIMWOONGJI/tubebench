function exportCsv(res, folder)
%EXPORTCSV Write results.csv and spectra.csv (one row per frequency).
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
writetable(S, fullfile(folder, 'spectra.csv'));
end
