# Work order WO-007: mains hum at the stepped-sine frequencies (proposal)

| | |
|---|---|
| Target version | not planned |
| Status | **proposal, recorded only** (owner decision 2026-11-04: keep it in a document, build nothing now) |
| Requested by | the owner (Woongji Kim), 2026-11-04, after the review of the stepped-sine analysis |
| Rules | as in CLAUDE.md |

## 1. The problem

Mains hum is interference at the mains frequency (60 Hz in Korea, 50 Hz elsewhere) and its
harmonics (120, 180, … Hz). It reaches the record electrically (microphone cables, preamplifiers,
ground loops) or acoustically (fans, transformers near the tube).

- The stepped-sine analysis fits a sine at the frequency of the step (3-parameter fit, IEEE 1057
  [4]; `docs/theory.md` section 5). A hum component at nearly the same frequency (closer than about
  the resolution of the fit, `1/T` of a block: 5–20 Hz with the 1.5.0 timing) cannot be told apart
  from the excitation: it adds to the tone of every channel with another amplitude and phase, so
  the ratio `H` between the channels is biased.
- Hum is a stable tone: it gives no scatter between the blocks (the coherence stays high) and it
  is part of the fit, not of the residual (the SNR does not see it). No validity mask catches it.
- The default steps (40 log steps, 120–4500 Hz) put **120 Hz (2 × 60)** and **4500 Hz (75 × 60)**
  exactly on a harmonic of 60 Hz, and **1619 Hz** 1 Hz from 1620 Hz (27 × 60).
- Size of the effect: hum 50 dB below the tone gives about 0.3 % in `H`, which is negligible. It
  matters at low excitation levels (0.2 Vpp direct drive) and on a channel with electrical hum.
- The swept sine is less sensitive: hum affects a few frequency lines only, and repetitions that
  are not locked to the mains average it down.

## 2. Options (none built)

1. **Warning**: the configuration check and the window warn before Start when a step lies within
   ± a few Hz of a mains harmonic (`environment.mainsFrequency_Hz`, 50 or 60).
2. **Shifted steps**: such a step is moved a few Hz off the harmonic (for example 120 → 123 Hz),
   and the frequency actually used is recorded.
3. **Measured hum**: the Background noise record gives the level of every harmonic per channel;
   warn only where the hum is significant against the tone (for example above −40 dB).

Recommendation if it is taken up: option 1 with the mains frequency as a setting, and option 3
when a background record exists; decide option 2 after a background record of the lab tube shows
whether the hum is significant at all.

## 3. Related

- `docs/assumptions_and_limitations.md` (Known limitations) names the limitation.
- `tim.dsp.sineResponse` (the fit) and `tim.app.steppedPlan` (the step frequencies).
