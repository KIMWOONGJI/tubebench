function [ms, rate] = sweepSineLevel(G, f, Trec, sweep, T)
%SWEEPSINELEVEL Mean square of the sine that sweeps through f, from a PSD.
%
%   ms = tim.dsp.sweepSineLevel(G, f, Trec, sweep)
%   [ms, rate] = tim.dsp.sweepSineLevel(G, f, Trec, sweep, T)
%
%   G      (Nf x C) one-sided PSD of a record that holds the sweep (Welch,
%          tim.plots.spectrum / res.pressureSpectrum) [unit^2/Hz]
%   f      (Nf x 1) its frequencies [Hz]
%   Trec   effective length of that estimate [s]: tim.dsp.welchDuration for
%          a Welch PSD (K hops of its K segments, a little less than the
%          record: the first and last 3 hops have less window weight)
%   sweep  struct fStart, fStop [Hz], duration [s], spacing ('LOG' | 'LIN')
%   T      duration of the sweep [s] (default sweep.duration; the DAQ-clock
%          duration of the sweep gate when known)
%   ms     (Nf x C) mean square [unit^2] of the sine as the sweep passes f,
%          the sine-equivalent level 10 log10(ms / p0^2) [dB SPL] that a
%          stepped sine of the same generator amplitude gives at f; NaN outside
%          [fStart, fStop] and where G is not finite or not positive
%   rate   (Nf x 1) sweep rate df/dt at f [Hz/s]
%
%   FORMULA (owner request 2026-11-15: the Spectrum view of a swept sine in
%   dB SPL like the stepped sine). A sine of amplitude A swept at the rate
%   fdot stays df/fdot in a band df and leaves there the energy
%   A^2 df / (2 fdot). The PSD G of an estimate of effective length Trec
%   holds the energy G Trec df in that band, hence
%       A^2 / 2 = G(f) * Trec * fdot(f),
%       fdot = f ln(fStop/fStart) / T   (logarithmic),   (fStop - fStart) / T   (linear),
%   the same relation as tim.dsp.sweepEquivalentAmplitude (A^2 = 4 fdot P / fs^2
%   with P the mean |DFT|^2 per bin: G = 2 P / (fs^2 Trec) for a rectangular
%   window). Display: noise, which is no sine, is scaled by fdot as well and
%   rises with f (3 dB per octave for a logarithmic sweep).

if nargin < 5 || isempty(T) || ~isfinite(T) || T <= 0, T = sweep.duration; end
f = f(:);
f1 = min(sweep.fStart, sweep.fStop); f2 = max(sweep.fStart, sweep.fStop);
if strncmpi(sweep.spacing, 'LOG', 3)
    rate = f * log(f2 / f1) / T;
else
    rate = (f2 - f1) / T * ones(size(f));
end
G(~(isfinite(G) & G > 0)) = NaN;
ms = G .* Trec .* rate;
ms(f < f1 | f > f2, :) = NaN;
end
