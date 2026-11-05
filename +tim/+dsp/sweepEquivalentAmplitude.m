function [A, rate] = sweepEquivalentAmplitude(refPower, f, fs, sweep, T)
%SWEEPEQUIVALENTAMPLITUDE Sine amplitude of a swept sine as it passes each frequency.
%
%   A = tim.dsp.sweepEquivalentAmplitude(refPower, f, fs, sweep)
%   [A, rate] = tim.dsp.sweepEquivalentAmplitude(refPower, f, fs, sweep, T)
%
%   refPower (Nf x 1) mean |Y|^2 per FFT bin of every frequency line and
%            repetition, Y the unnormalised DFT of the windowed record
%            (tim.dsp.sweepResponse: out.refPower) [V^2]
%   f        (Nf x 1) frequencies of the lines [Hz]
%   fs       sample rate [Hz]
%   sweep    struct fStart, fStop [Hz], duration [s], spacing ('LOG' | 'LIN')
%   T        duration of the sweep on the DAQ clock [s] (the matched-filter
%            duration of tim.dsp.sweepResponse, excitation.sweepDuration_s);
%            default sweep.duration
%   A        (Nf x 1) amplitude [V peak, the unit of the record] of the sine
%            that sweeps through f; NaN outside [fStart, fStop] and where
%            refPower is not finite or not positive
%   rate     (Nf x 1) sweep rate df/dt at f [Hz/s]
%
%   FORMULA (1.6.0, WO-006 stage 1; docs/theory.md, section 3C)
%       A(f) = (2/fs) * sqrt( fdot(f) * P(f) ),   P = refPower
%       fdot = f * ln(fStop/fStart) / T   (logarithmic),   (fStop - fStart) / T   (linear)
%   Energy (Parseval): a sine of amplitude A swept at the rate fdot stays
%   df/fdot in a line of width df, so the line holds the energy
%   A^2 df / (2 fdot). The one-sided DFT energy of the line is
%   2 sum|Y|^2 / (N fs) with n = df N / fs bins (N = FFT length), hence
%   A^2 = 4 fdot sum|Y|^2 / (n fs^2) = 4 fdot P / fs^2. The same follows by
%   stationary phase: |X(f)|^2 = A^2/(4 fdot) and |Y| = fs |X|. Zero padding
%   (N) and the number of repetitions do not enter (P is a mean per bin and
%   repetition). The window must be 1 where the sweep passes f (the sweep
%   gate inside the band; the 10 ms tapers of the fallback window lie at the
%   ends of the excitation). For a linear system the response of a channel
%   is G(f) times the drive, so A(f) of a microphone channel is |G(f)| times
%   the generator amplitude, as a stepped sine at f would give; the
%   generator spectrum itself is smooth only on the scale of sqrt(fdot)
%   (Fresnel ripple near the ends of the sweep and the window ramps).

arguments
    refPower (:,1) double
    f (:,1) double
    fs (1,1) double {mustBePositive}
    sweep struct
    T double = []
end
if isempty(T) || ~isfinite(T) || T <= 0, T = sweep.duration; end
f1 = min(sweep.fStart, sweep.fStop); f2 = max(sweep.fStart, sweep.fStop);
if strncmpi(sweep.spacing, 'LOG', 3)
    rate = f * log(f2 / f1) / T;
else
    rate = (f2 - f1) / T * ones(size(f));
end
P = refPower;
P(~(isfinite(P) & P > 0)) = NaN;
A = 2 / fs * sqrt(rate .* P);
A(f < f1 | f > f2) = NaN;
end
