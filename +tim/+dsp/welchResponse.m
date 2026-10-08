function out = welchResponse(x, fs, opts)
%WELCHRESPONSE Relative responses for stationary broadband (noise) excitation.
%
%   out = tim.dsp.welchResponse(x, fs, opts)
%   opts: refChannel (1), nfft (8192), overlap (0.5), fRange, fGrid
%
%   H1 estimator H_c = G_cr / G_rr, G_cr = <X_c X_ref^*> (cpsd/pwelch, Hann
%   window) and the magnitude-squared coherence g2 = |G_cr|^2 / (G_rr G_cc) (mscohere
%   definition). Optional linear interpolation (re/im) onto fGrid; the
%   Welch grid (fs/nfft) is fine compared with the variation of H.
%   Valid for stationary random excitation such as the 33220A NOISe
%   function; for sweeps use tim.dsp.sweepResponse.

o = struct('refChannel', 1, 'nfft', 8192, 'overlap', 0.5, 'fRange', [0 fs/2], 'fGrid', []);
fn = fieldnames(opts); for i = 1:numel(fn), o.(fn{i}) = opts.(fn{i}); end
ref = o.refChannel;
C = size(x, 2);
win = hann(o.nfft, 'periodic');
nov = round(o.overlap * o.nfft);
[Grr, f] = pwelch(x(:, ref), win, nov, o.nfft, fs);
H = ones(numel(f), C); coh = ones(numel(f), C); snr = nan(numel(f), C);
for c = 1:C
    if c == ref, continue; end
    % NOTE: MATLAB cpsd(a, b) = <A .* conj(B)>; hence cpsd(x_c, x_ref)
    % = <X_c X_ref^*> is the cross-spectrum needed for H = X_c / X_ref.
    % (Verified against tfestimate; the reversed argument order conjugates H.)
    Gcr = cpsd(x(:, c), x(:, ref), win, nov, o.nfft, fs);
    Gcc = pwelch(x(:, c), win, nov, o.nfft, fs);
    H(:, c) = Gcr ./ Grr;
    coh(:, c) = abs(Gcr).^2 ./ (Grr .* Gcc);
end
nAvg = floor((size(x, 1) - nov) / (o.nfft - nov));
keep = f >= o.fRange(1) & f <= o.fRange(2);
f = f(keep); H = H(keep, :); coh = coh(keep, :); snr = snr(keep, :);
if ~isempty(o.fGrid)
    fg = o.fGrid(:);
    H = interp1(f, real(H), fg) + 1j * interp1(f, imag(H), fg);
    coh = interp1(f, coh, fg); snr = interp1(f, snr, fg); f = fg;
end
% Coherence-based SNR estimate for the relative response: g2/(1-g2)
snr = 10 * log10(coh ./ max(1 - coh, eps));
out = struct('f', f, 'H', H, 'coherence', coh, 'snr_dB', snr, 'nAvg', nAvg * ones(numel(f), 1), ...
    'refChannel', ref, 'method', 'Welch H1 (cpsd/pwelch), Hann window', 'options', o);
end
