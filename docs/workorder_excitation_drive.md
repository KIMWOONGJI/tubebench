# Work order WO-004: the excitation drive chain in the window (1.3.0)

| | |
|---|---|
| Target version | 1.3.0 |
| Status | **done**, version 1.3.0 (2026-10-13), branch `wo-004` (worktree `tubebench-wo004`): sections 2-4 built, the hardware check of the load setting passed with the owner on 2026-10-13 (section 5, steps 1-2), the role names of the window added the same day (decision 9); the full suite in section 6. **Next:** the merge into `main` |
| Requested by | the owner (Woongji Kim), 2026-10-12, after a review of the voltage conditions of the EXCITATION section |
| Mock-up | https://claude.ai/artifact/REcrLazJgT7HGAaHJvNivP (version 3; the owner's decisions and the safety criteria) |
| Rules | as in CLAUDE.md; a change of the instrument communication needs a short hardware check with the owner present; the bus-traffic fixtures are regenerated only for an owner-approved change |
| Decisions | owner, 2026-10-12, all listed in section 1 |

## 1. Decisions (owner, 2026-10-12)

1. **Unit.** Levels stay in **Vpk**; the window also shows the Vrms of a level where there is room.
   For noise the rms value is the meaningful one (crest factor 3.3).
2. **Loudspeaker check.** The loudspeaker power is computed at the **nominal impedance**,
   P = V_rms² / Z (the convention of the rated power, IEC 60268-5), and compared with the test
   limit (`loudspeaker.maxPower_W`):
   - below 80 % of the limit: OK;
   - 80-100 %: "Near limit" (the measurement may run; IEC 60268-5 lets the real impedance fall to
     80 % of the nominal one, so the real power can be up to 1.25 × the estimate);
   - above 100 %: refused.
   The test limit is at most the rated power (`loudspeaker.ratedPower_W`).
3. **Generator output load.** With an amplifier, the generator's load setting (`OUTP:LOAD`) is the
   **amplifier's input impedance**, entered in the window ("Amp input [Ω]": a number from the data
   sheet such as 50 or 600, or High Z; above 10 kΩ the generator is set to INF). The programmed
   level is then the voltage at the amplifier input. With **direct drive the load stays High Z**
   (`INF`): the loudspeaker impedance changes with frequency, so the generator sets the
   open-circuit voltage, as in 1.2.1.
4. **Gain** is entered as a factor (×, Vout/Vin). Its tooltip gives the dB conversion: entering
   the dB value of a 40 dB amplifier (×100) as ×40 would give 2.5 × the estimated voltage.
5. **`generator.maxVpp` is the open-circuit voltage** at the generator terminals [Vpp], whatever
   the load setting. With `INF` nothing changes; with a numeric load R the programmed level is at
   most maxVpp · R / (R + R_s).
6. **The near-limit threshold is 80 %** (decision 2).
7. **With an amplifier the level may be given at the loudspeaker** ("Speaker [Vpk]", the default
   when the gain is known); without a gain only "Amp input [Vpk]" is possible and Start is refused.
8. **Driver change approved**: the 33220A driver accepts a numeric load (1 Ω - 10 kΩ, manual
   p.189). The bus traffic of a High Z session does not change. A numeric load is checked on the
   instrument when an amplifier is connected (section 5).
9. **Role names, not product names** (owner, 2026-10-13, during the hardware check): the
   INSTRUMENTS lamps read **Generator** and **DAQ** (was "LAN-XI"), and the sentences of the window
   say "the DAQ" (was "the LAN-XI module"). The connection checklist shows each driver step after
   the lamp label of its role: "Generator: connect (33220A, SCPI)", "DAQ: connect (LAN-XI, REST)",
   "DAQ: recorder state Idle", "DAQ: open recorder", "DAQ: TEDS detection", "DAQ: channel setup →
   streaming". The product stays where it identifies the instrument: the "In use" line and the
   tooltips (display name, model, serial number), the Instruments table, and the messages about
   the module's own status flags (LAN-XI INVALID / OVERRUN).
10. **Instrument guide** (review of the add-instrument skill, same day): the skill itself only runs
    `docs/adding_an_instrument.md` and needed no change; the guide, the templates and the
    contract test follow decisions 5 and 9 (section 3).

Not in this work order (proposed the same day, no decision yet): an acoustic pressure equalizer
(a constant incident sound pressure, stepped sine only with the 33220A), and the display of the
incident SPL of every measurement as its first step.

## 2. What the operator sees

EXCITATION rows (the panel keeps 7 field rows; height limit 930 px, `TestGui/leftPanelFitsWithoutScrolling`):

| Row | Contents |
|---|---|
| Signal | Swept sine / Stepped sine (unchanged) |
| Frequency, Sweep duration / Repetitions | unchanged |
| Amplifier | none (direct drive), power amplifier, typed models (unchanged) |
| Amplifier gain [×] / Amp input [Ω] | gain (×; dB conversion in the tooltip) and the amplifier input impedance (editable list: High Z, 50, 600, 10000). Direct drive: the second label reads "Generator load" and the list is fixed at High Z |
| Loudspeaker [Ω] / Test limit [W] | nominal impedance, test power limit (the rated power in the tooltip and below) |
| Level | the level reference (Speaker [Vpk], and Generator [Vpk] in direct drive or Amp input [Vpk] with an amplifier), the level, its Vrms, the expected duration |

Below the rows, a white box of three lines replaces the drive sentence (as the mock-up; the
owner asked for both bars, side by side, 2026-10-12):

1. the signal path: the generator (in Vpp, as its display shows it, and what the number means:
   open-circuit or at the amplifier input), the gain, the loudspeaker in Vpk;
2. two meters side by side, each a bar of its share of the limit with a tick at 80 %, the share
   and a state box: Speaker (power at the nominal impedance against the test limit: OK / Near /
   Above, Gain? without a gain) and Generator (open-circuit voltage against `generator.maxVpp` or
   its own range: OK / Above); the numbers in the tooltips;
3. the largest level and the criterion that sets it (the loudspeaker test limit,
   `generator.maxVpp`, or the generator's own output).

## 3. Changes

- `tim.app.driveEstimate(cfg, vpp, kind)`: the kind of signal (noise: rms = peak / crest factor of
  the driver, otherwise a sine); new fields `Vspk_rms`, `fraction` (of the test limit), `state`
  ('ok' | 'near' | 'over' | 'unknown'), `crest`; the open-circuit voltage for any numeric load.
- New `tim.app.driveLimits(cfg, kind)`: every criterion as the largest loudspeaker voltage and the
  largest programmed level it allows, and the one that sets the maximum. Used by the window, the
  excitation confirmation and the tests.
- `tim.app.generatorAmplitude`: also with an amplifier (needs the gain).
- `tim.app.validateConfig`: `generator.load` 'INF' or a number as text; direct drive needs 'INF'
  (was: '50' refused); the excitation levels against `maxVpp` as open-circuit voltage;
  `ui.amplitudeAt = 'loudspeaker'` with an amplifier needs the gain (was: a warning).
- Contract (`tim.instr.SignalSource`, `docs/instrument_interface.md`): `capabilities().source.loadRange`
  (optional, [min max] Ω) for a source that accepts a numeric load; the level range at a numeric
  load scales from the INF values by R / (R + R_s); `generator.maxVpp` is an open-circuit voltage.
  New static helpers `levelRange(source, load)` and `openCircuitFactor(source, load)`.
- `tim.instr.Keysight33220A`: `Load` 'INF' or a number 1-10000; `OUTP:LOAD <R>` and its read-back
  for a numeric load; the amplitude limit as open-circuit voltage; `loadRange` [1 10000].
- `MeasurementSession`: the power check and the confirmation with the kind of signal; the
  confirmation names what the programmed level means and the loudspeaker check (msg, both
  languages).
- Window: section 2.
- Role names (decision 9): `describe().labels.acquisition` and `texts.noun` of the LAN-XI driver
  'DAQ'; the drivers' checklist labels are short lower-case phrases without the role
  (`'connect (33220A, SCPI)'`, `'open recorder'`), and the window (`connLabels`) puts the lamp
  label of the step's role in front (both labels joined by " + " for a step of both roles).
- Instrument guide (decision 10): `templates/instrument/TemplateSource.m` checks the open-circuit
  voltage against `generator.maxVpp` (`openCircuitFactor`, `levelRange`; it compared the
  programmed level, so at its load '50' a level of 2 × maxVpp would have reached an open input) and
  accepts a `loadRange` (`supportsLoad`); the templates' checklist labels and lamp-label comments
  follow decision 9; `docs/adding_an_instrument.md` (level check, labels, checklist texts, the
  demo example); new contract case `TestInstrumentContract/levelLimitIsOpenCircuit` (every
  source driver and template at each listed load other than INF).
- Docs: user guide (EXCITATION, configuration keys, troubleshooting, lamps, checklist, closing),
  instrument interface (labels, nouns, checklist texts), hardware status (section 5), README.

## 4. Tests (as built)

- `TestConfiguration/amplifierInputIsTheGeneratorLoad`: a numeric load with an amplifier, the
  open-circuit voltage at 600 Ω, `maxVpp` as open-circuit voltage, the direct-drive rule, a load
  above 10 kΩ and `'inf'` refused, the warnings for a load that differs from the amplifier input
  and for an unknown input impedance, `levelRange` / `openCircuitFactor` of the 33220A.
- `TestConfiguration/driveStatesAndLimits`: ok / near / over / unknown at the nominal impedance,
  noise with the crest factor, the criterion that sets the maximum (loudspeaker, `maxVpp`, the
  generator's own range), a test limit above the rated power.
- `TestConfiguration/loudspeakerVoltageGivesTheGeneratorLevel`: `generatorAmplitude` also with an
  amplifier of known gain, refused without one.
- `TestInstruments/generatorAtTheAmplifierInput`: the 33220A at load 600 (`OUTP:LOAD 600`, its
  read-back, the open-circuit limit in `configure*` and before `OUTP ON`, the smallest level),
  `INF` without a read-back query, invalid loads refused before any I/O.
- `TestGui/excitationChainControls` (rewritten): the labels, the amplifier input setting the load
  (typed, above 10 kΩ, not a number), the level reference following the amplifier and the gain,
  the three lines and their states (ok, near, over), direct drive with the maximum set by
  `maxVpp`, the stored level and `metadata.drive` (state, Vrms) of a measurement.
  `TestGui/amplifierWithoutGainIsNeitherEstimatedNorDriven`: the new texts and states.
- `TestEndToEnd/operatorMessages`: the confirmation at a 600 Ω amplifier input, both languages.
- `TestBusTraffic`: unchanged fixtures (High Z).

## 5. Hardware check (owner present; only the generator, output OFF)

1. Connect with an amplifier chosen and Amp input 600 Ω: the SCPI log shows `OUTP:LOAD 600` and
   its read-back 600; the generator's display shows the load setting; the output stays OFF.
2. Disconnect, direct drive: `OUTP:LOAD INF` at the next Connect.
3. With an amplifier connected (if one is available), a short measurement at a level the owner
   approves.

**Result (2026-10-13, owner present, the wo-004 version on the real instruments, output OFF
throughout):**

1. **Passed.** Amplifier "power amplifier", Amp input 600 Ω, Connect: the Connect completed, so the
   driver's read-back `OUTP:LOAD?` was 600 (`setLoad` stops the Connect with `tim:gen:verify`
   otherwise); the generator's display showed the 600 Ω load.
2. **Passed.** Disconnect, direct drive, Connect, Disconnect; then a read-only query of the
   generator: `OUTP:LOAD?` 9.9E37 (INF), `OUTP?` 0, `SYST:ERR?` +0,"No error".
3. Not done (optional).

Before the check, the first two Connects of the day (1.2.1, about 11:51) failed with
`tim:scpi:connect` while ping, the generator's MAC address and the ports 5025 and 80 answered; a
third Connect a few minutes later worked. The cause is not known (the MATLAB text of the failure
is only in the connection log).

## 6. Verification (2026-10-12, software only)

- Batch MATLAB R2022b on the branch, split because the owner's MATLAB was open (0.4-2.9 GB
  free): the 15 classes without graphics (`-nojvm`) and the 8 with graphics. The bus-traffic
  fixtures pass unchanged (a High Z session sends the same commands as 1.2.1).
- Two failures of the first graphics run, fixed and re-run: a comment of the window named the
  generator model (`TestGui/noInstrumentNamesInWindowOrSession`), and `SignalSource.loadOhm`
  trimmed spaces, so `' 50'` passed the configuration check (review analysis-6: exact text only;
  `TestEndToEnd/driveEstimateGeneratorLoad`). Re-run of the affected classes and tests: 153 / 153;
  then the three window tests of the drive after the last change (an HTML escape): 3 / 3.
- 361 tests in 23 classes (2026-10-12); 364 with the new contract case (decision 10, three
  source drivers).
- Screen captures of a visible simulation window (separate MATLAB, no clicks or typing): direct
  drive, an amplifier without a gain, 600 Ω ×10 at 0.707 Vpk, near the limit (3.79 Vpk) and above
  it (4.1 Vpk). The three lines fit; the control panel needs no scrolling (930 px, the limit).
- Code Analyzer: no new message in the changed files.
- The two meters (owner request, the same evening): built from plain panels in grids (the bar
  is four panels: filled part, track, the 80 % tick, track), so the box stays 45 px. Window tests
  of the drive and the panel height 4 / 4; the five set-ups captured again: the meters, their
  states and the three lines fit.
- **Full suite in one run** (2026-10-13, after decisions 9-10 and version 1.3.0; `run_tests()` in
  the owner's idle MATLAB R2022b, hidden windows only): 364 tests, 363 passed, 1 failed:
  `TestGui/measurementBeforeViewsAreReady`, a timing test (a 1.5 s timer opens a tab during a
  measurement and the background queue must wait), which touches none of the changed code; run
  again alone right after: passed. Code Analyzer: the same message counts as before in the
  changed files.
