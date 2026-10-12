# Work order WO-003: follow-up of the hardware check of 2026-10-12 (1.2.1)

| | |
|---|---|
| Target version | 1.2.1 |
| Status | **sections 1, 2 and 6 done**: built on branch `wo-003` on 2026-10-12, the owner's hardware check of sections 1 and 2 passed (`docs/hardware_status.md`, "Hardware check of 1.2.1"), the rounded paths of section 6 confirmed by the owner on screen captures; version 1.2.1, merged into `main` on 2026-10-12. **Still open:** the after-merge items of section 3, the owner decisions of section 4 and the question of section 5 (written 2026-10-12 after the owner's hardware check of 1.2.0) |
| Requested by | the owner (Woongji Kim), during and after the hardware check |
| Rules | as in CLAUDE.md; a change of the instrument communication needs a short hardware check with the owner present; the bus-traffic fixtures are regenerated only for an owner-approved change |
| Decisions | owner, 2026-10-12: (1) the connection check before every measurement / calibration with an automatic reconnect - **approved, including the regeneration of the bus-traffic fixtures**; (2) the idle check every 60 s - **yes**; (3) the loudspeaker voltage as the level in direct drive - **in 1.2.1**. Branch `wo-003` |

## 1. Generator connection dropped by the 33220A (defect, known since 1.1.0)

Observed on 2026-10-12 (`docs/hardware_status.md`, observation 1 of the check):
- After an idle period (5–43 min) the first Start failed on its first SCPI commands. The instrument
  had dropped the connection without the PC noticing and answered with a reset.
- The drop is **silent**: the Windows TCP state stayed "established" until the next request (no
  FIN, no CloseWait), so it can only be found by sending something.
- The window showed a MATLAB message in Korean, and the output "could not be confirmed off". The
  output had not been armed.
- Disconnect → Connect restored the connection.

Tasks:
1. `ScpiTcpTransport`: English errors (`tim:scpi:connectionLost` for a failed write, `tim:scpi:timeout`
   for a missing answer) and `isOpen()` false after a failed write; `reopen()`. (Found while
   building it: `tcpclient` reports the reset only in a background handler that prints a stack
   trace in the command window - `ErrorOccurredFcn` is not called and the print cannot be
   suppressed; the pending `readline` runs into its time-out. Harmless: the check below re-opens
   the connection.)
2. Before every measurement, calibration, background-noise recording and Test (`tim.val.*`), check
   the generator connection with a short query (`OUTP?`). If the connection is gone:
   - open it again;
   - check that `*IDN?` names the same serial number;
   - send `OUTP OFF` and `OUTP:LOAD <load>` again;
   - log "Generator connection was closed by the instrument and re-opened";
   - continue.
   If reconnecting fails, stop with an English error (`tim:scpi:connectionLost`) and turn the
   Generator lamp red. The output is never armed before the check has passed.
3. An idle check every 60 s (owner: yes), never while `Busy`, a session operation or a stream is
   active. It reconnects a dropped connection and shows a lost connection on the lamp at once. If
   the 33220A drops only idle connections, it may also prevent the drop.
   Decided later the same day (owner, after the static IP did not stop the drops): a connection
   idle for more than 30 s is replaced before use without sending anything on it, so the reset
   and MATLAB's stack trace do not occur; a connection used more recently is checked with OUTP?.
4. Tests:
   - the local fake instrument (as in `TestInstruments`) closes or resets the socket while the
     session is idle;
   - the next measurement reconnects (or fails with the English error);
   - the bus-traffic scenario for the reconnect.
5. Hardware check:
   - provoke the drop (wait idle until it happens, or have the owner switch the 33220A's LAN off
     and on), then confirm the automatic reconnect and that the output stays off;
   - in the same session, keep logging the Windows TCP state, to see whether the instrument closes
     the connection with a FIN or drops it silently.

## 2. EXCITATION section of the window (owner requests, 2026-10-12)

1. **Amplifier gain.**
   - The field shows "×1" when the amplifier is "none (direct drive)", and the owner read it as a
     field that does not take a plain number. Make the number entry obvious: unit in the label, a
     plain number in the field.
   - Make it visible that another amplifier can be typed into the Amplifier list (the lab
     configuration lists only "none (direct drive)").
2. **"Loudspeaker [Ω]" and "Power limit [W]" on one row.**
3. **Name the power limit as the loudspeaker's** (e.g. "Speaker power limit [W]").
4. **Generator output load (High Z / 50 Ω) chosen in the window.**
   - Today it is set only in the configuration (`generator.load`); the driver sends `OUTP:LOAD` at
     Connect.
   - Fill a list from the selected driver's `capabilities().loads`, store the choice with every
     measurement, and explain it next to the control and in the user guide. On the 33220A the
     setting changes only the meaning of the programmed amplitude; the source impedance stays 50 Ω.
   - Direct drive (owner decision 2026-10-12: in 1.2.1):
     - keep the generator at High Z;
     - let the operator enter the loudspeaker voltage;
     - compute the generator voltage from the driver's source impedance (33220A: 50 Ω) and the
       loudspeaker impedance;
     - record both values.
   - `OUTP:LOAD 8` is not recommended. The level limits, the drive estimate, the confirmation text
     and the configuration check assume INF or 50. The setting also stays in the 33220A's memory
     for other users.
   - Facts for the user guide: with direct drive the loudspeaker gets V × 8/58 of the programmed
     open-circuit voltage, and at most about 2.8 Vpp (about 0.12 W).
5. Tests in `TestGui` for the new labels, layout and the load list. Check the layout with a real
   screen capture, not with `exportapp`.

## 3. After the merge of 1.2.0 (from `docs/hardware_status.md`, "After the merge")

1. Rewrite `config/user_config.json` in the new layout (D7, approved 2026-10-11): load it, save it
   with `tim.app.saveConfig`, review the diff, and check that it loads without a warning.
2. Reprocess the five lab folders into new folders (centred frequency lines). **Open owner
   decision:** which calibration to use. Recommended: calibrations recomputed from the saved raw
   switching sweeps with a small new function that writes new calibration files.

## 4. Open owner decisions carried over from 2026-10-11

1. The calibration for item 3.2 (above).
2. An extrapolated gate ramp before the sweep start, for a sweep that starts without the margin.
   Recommended in simulation:
   - with an output-on click, 0.63 % error instead of 60 %;
   - without a click, 3.4 % instead of 2.0 %.
3. Show the mapping of the saved results in the mapping question of File > Open measurement…
   (recommended).
4. Keep "Esc = recorded mapping" and the cancel rule of `ask()` (recommended).

## 5. To look into (no change decided)

* Signal-check levels: 66–72 dB SPL at the first Connect of 2026-10-12, then 82–85 dB SPL at every
  later Connect, while the pre-roll of a measurement read about 45 dB SPL. Find out whether this is
  low-frequency settling after the 0.7 Hz high-pass, or room or electrical noise. If it is
  settling, make the check exclude it.

## 6. Rounded microphone-swap paths in the Calibration view (owner request 2026-10-12, built 2026-10-12)

The dashed swap paths and the animation of the Calibration view turn with sharp 90° corners
(local `calPath` and `animateCalMics` in `Tubebench.m`; the dashed line has 4 vertices). The owner
wants rounded corners that adapt to every tube configuration (diameter, s1/s2, L1/d/L2,
calibration ports, tubeDrawing). Agent design review, 2026-10-12:

- **Corners as circular fillets.** One radius per drawing, computed in `drawTube3D` (new field
  `swapRadius`): r* = max(0, min(0.4·sMin, h₁/3, h₁ − 8, sMin − 2ρ − 1, lift₁ − zExit − 1)), set to 0
  below 1 mm. Here sMin is the smallest non-zero port gap, h₁ = lift(1) − 2, 8 mm is the arrowhead
  plus a straight shank, ρ is the microphone or plug radius, and zExit is the height at which the
  microphone tip leaves its holder. About 11.6 mm in the lab tube. Each path uses
  min(r*, |xb − xa|/2).
- **Path function.** A new pure function `+tim/+gui/calSwapPath.m` returns the vertices and the
  point at a fraction of the arc length. The dashed line and the animation both use it, and the
  local `calPath` is removed.
- **Why fillets.** The turning radius is bounded, there is no overshoot (each arc stays inside its
  corner triangle), the straight parts are unchanged, and the arc length is exact. Two paths of
  the same span never cross.
- **Edge cases.** Adjacent or distant ports, a zero gap (L1 = d = L2 = 0), and spacings of 1–10 mm
  (corners stay sharp below 1 mm). Other calibration positions and steps with 3 microphones moving.
  Diameters of 1–500 mm (the lowest point stays above the tube).
- **Tests.**
  - New `TestCalSwapPath` (no window): r = 0 matches the old path; exact endpoints; continuity;
    turning ≤ 6°; points inside the box; straight shank ≥ 8 mm; a width × radius table; no crossing.
  - Add to `TestTube3D` (swapRadius over several tube configurations) and to `TestGui` (the paths in
    a simulated calibration).
  - Screen captures of several configurations, from a separate MATLAB with the owner's consent.
- **Size.** About 330 lines in 7 files. The constants 0.4 and 1/3 are for the owner to confirm on
  the captures.
- **Separate finding.** `lift` ignores the holder height, so with a very tall holder a microphone
  would be drawn sliding through it. This does not apply to the lab tube.

**Built (branch `wo-003-paths`, 2026-10-12), as designed:**

- `drawTube3D` returns `M.swapRadius` (local `swapRadius`): sMin from the sorted port positions
  (gaps below 1 µm count as zero), h₁ = lift(1) − 2, ρ = max(microphone radius, 3.6 mm plug),
  zExit = holder top − microphone tip (the lift at which the tip leaves the holder). Lab tube:
  **11.6 mm** (0.4 × 29 mm limits; h₁/3 = 24.2, h₁ − 8 = 64.5, sMin − 2ρ − 1 = 20.8,
  lift₁ − zExit − 1 = 58.75 mm).
- `+tim/+gui/calSwapPath.m`: vertices (two quarter arcs of 16 segments, repeated vertices removed)
  and length, or the points at fractions s of the exact arc length (straight parts and true
  arcs; s ≤ 0 and s ≥ 1 give the exact end points). The radius used is min(r, |xb − xa|/2) and, as
  a guard outside the design range, never more than zl − z0. The cosine easing stays in
  `animateCalMics`, so the motion has the same timing as before.
- `animateCalMics` uses it for the animation (z0 = 0, zl = lift(i)) and the dashed line
  (z0 = zHandle + 2), with the same radius; the local `calPath` is removed; the arrowhead is
  unchanged.
- Tests: `TestCalSwapPath` (8 tests, the list above); `TestTube3D/swapRadiusOverTubeConfigurations`
  (lab tube 11.6; s1 = 1 and 9 mm → 0; s1 = 10 mm → 1.8; s1 = 200 mm → 11.6; s1 = s2 = 200 mm →
  h₁/3 = 24.2; L1 = d = L2 = 0 → 11.6; D = 1 and 500 mm → 11.6; an 80 mm holder → 0) and the
  field in `TestTube3D/returnedStruct`; `TestGui/calibrationDiagramDrawnOnDemand` now also runs a
  step with three movers (configuration II of ch2 → configuration I of ch3) in the hidden window
  and checks the dashed paths (one line and one arrowhead per mover, from portX(from) at
  zHandle + 2 to portX(to), none below that, turning ≤ 6°) and the final positions. 357 tests.
- Verified 2026-10-12 in batch MATLAB R2022b (`-nojvm`): `TestCalSwapPath` 8 / 8 passed; Code
  Analyzer: no new message in the changed files (`Tubebench.m` keeps its 21 old NOCOMMA notes).
  `TestTube3D` and `TestGui` need graphics and more than 2 GB of free memory, so they ran with the
  full suite after the owner's hardware check (2318d8e: 357 / 358; the failure was the test calling
  the private `animateCalMics`, now hidden instead, c5eb55b). Before the merge the full suite ran
  again on the release state (version 1.2.1 on b9a3dca), split over two batch MATLAB processes
  because the owner's MATLAB was open: 15 classes without Java (207 tests) and the 8 classes with
  graphics (151 tests) - **358 / 358 passed** (2026-10-12, 19:16 and 19:41).
- Screen captures (a separate visible MATLAB, with the owner's consent, 2026-10-12) of seven
  configurations: the lab tube with ports 1–2 (a step with three movers, and a plain swap), 2–3 and
  1–4 (radius 11.6 mm); s1 = 10 mm (1.8 mm); L1 = d = L2 = 0; D = 200 mm. Every path is rounded,
  inside the drawing and clear of its neighbours. **The owner confirmed the constants 0.4 and 1/3
  on them** (2026-10-12). They also showed two older label overlaps, not caused by the paths: the
  port labels when two microphones share a position, and "EMPTY 75 mm section" over "M2 (b)" at
  D = 200 mm. The same captures showed the amplitude label of the EXCITATION panel cut to
  "Generator [V…"; its label column is now 130 px, and the gain / load row has its own widths, so
  "High Z" is not cut either (b9a3dca).
