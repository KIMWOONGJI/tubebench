# Work order WO-005: the two-load transfer matrix in the window (1.4.0)

| | |
|---|---|
| Target version | 1.4.0 |
| Status | **software built** (sections 3-8, 2026-10-14, branch `wo-005`, worktree `tubebench-wo005`; section 11). **Next:** the owner's hardware check (section 9), then version 1.4.0 and the merge. `main` keeps 1.3.2 until then |
| Requested by | the owner (Woongji Kim), 2026-10-13 and 2026-10-14, after the review of the anechoic criterion: the lab termination reflects (\|R_term\| 0.85 at 125 Hz, 0.25 at 4 kHz), so τ, α_d and TL_τ are masked in the whole band, and the thin-element Z_t does not apply to the thick lab specimens |
| Rules | as in CLAUDE.md; hardware results only from real measurements with the owner present; raw data are never overwritten |
| Decisions | owner, 2026-10-14, all listed in section 1 |

## 1. Decisions (owner, 2026-10-14)

1. **Method.** MEASUREMENT gets a Method selector:
   - **One load (anechoic)**: today's measurement. This is the default in `defaultConfig` and in
     the lab file `config/user_config.json`.
   - **One load, symmetric specimen**: the one-load transfer matrix of ASTM E2611 [3] for a
     front-to-back symmetric and reciprocal specimen. It is labelled as an assumption wherever it
     appears. Most of the owner's specimens are asymmetric, so it is never a default.
   - **Two loads (ASTM E2611)**: section 5.
2. **Loads.**
   - A load is a termination **kind** (Absorber, Rigid cap, Open end) at a **place** (Tube end,
     Joint).
   - The absorber exists only at the tube end.
   - Any pair with A ≠ B is allowed. Defaults: A = Absorber at tube end, B = Rigid cap at tube end.
   - The labels carry no "(default)" or "(ASTM)" mark. The ASTM E2611 / Brüel & Kjær example (open
     and approximately anechoic) is named in the tooltip and the user guide.
3. **Remembered choice.**
   - The window remembers Load A, Load B and the repeat setting from the last two-load Start. They
     are MATLAB preferences of the Windows user, stored per configuration file (the lab and the
     virtual tube do not overwrite each other).
   - A hidden window (tests) neither reads nor writes them.
   - The Method always starts at One load.
   - Without a record, the configuration's values apply.
4. **Sequence and saving.**
   - The sequence is A → B → A'. Repeating load A is on by default.
   - Every load is saved at once as an ordinary measurement folder. The two-load result is saved in
     its own pair folder, which names the load folders.
   - Saved measurements can also be paired later (File menu).
5. **A' check.** The repeat is compared through T(A, B) and T(A', B). T does not depend on the
   termination, so re-packing the absorber is not counted as a change; a moved specimen or
   microphone is.
6. **Limits.**
   - The condition number of Q is computed after scaling each column to unit length: `condQ ≤ 10`
     (`analysis.condQMax`).
   - The reciprocity error `|det T − 1| ≤ 0.1` (`analysis.reciprocityTol`) is a flag, not a mask.
   - The loads must be at most 1 K apart in temperature and at most 30 min apart in time; beyond
     that the window warns.
   - Geometry, analysis band, microphone mapping, calibration and excitation must be the same in
     both loads, or nothing is computed.
7. **Level.**
   - Load B uses the generator level of load A by default.
   - The operator may lower it ("Load B level: same as A / lower by x dB"). Raising it needs the
     owner's approval, as always.
   - The window shows the peak sound pressure of every load and warns when B is 10 dB or more
     above A. A rigid cap raises the level at the tube resonances (estimated +10–20 dB), and a
     specimen that is not linear at that level would give inconsistent loads.
8. **Placement in the window.** The control panel is at its height limit (930 px,
   `TestGui/leftPanelFitsWithoutScrolling`).
   - **Control panel:** MEASUREMENT gets only the Method row, shared with the background-noise
     button.
   - **Termination selection:** in **Setup > Tube setup**, a Termination box above the Geometry
     table.
     - One load: one row, "Termination [kind] at [place]".
     - Two loads: Load A, Load B and "Repeat load A at the end".
     - A muted line below the rows describes the swap and the distance of the termination face.
   - **3D model:** follows the selection. With two loads, "Show: Load A | Load B" in the header
     tools switches between them.
   - **Procedure:** runs in **Measurement > Two-load**, built like the Calibration view: operator
     bar, the 3D model of the load to mount, the step list, condQ and the A' check.
   - The first prompt names load A, so a Start without a look at Tube setup still confirms the
     loads.
   - The style of the window does not change.
9. **Termination record.** Every measurement, one-load included, records its termination in the
   metadata. In simulation the virtual rig uses the selected termination.
10. **Branch.** `wo-005` in the worktree `tubebench-wo005`; merge after the hardware check and the
    owner's approval.

## 2. Background: conditioning of the lab loads

The loads give the boundary states `[p_R; Z_c u_R]` at the rear face of the specimen, one column
per load. Their angle decides how much the measurement errors grow in `T = P·Q⁻¹`: with the columns
scaled to unit length, `condQ = cot(θ/2)`.

Estimate from the six lab folders of 2026-10-12/13: the measured R_term of the absorber against
ideal loads, column-normalised condQ, maximum over each band:

| Load B (A = Absorber) | 120–250 Hz | 250–500 Hz | 0.5–1 kHz | 1–4.5 kHz |
|---|---|---|---|---|
| Rigid cap at tube end | 6.0 | 2.9 | 10.8 | 6.5 |
| Rigid cap at joint | 49 | 12.8 | 5.5 | 5.0 |
| Open end at tube end | 3.9 | 19 | 14.5 | 8.8 |
| Open end at joint | 1.6 | 3.3 | 12.7 | 6.3 |

The positions come from `tubeDrawing`: the tube end is 291 mm and the joint 41 mm downstream of
M4. The open end uses an unflanged-pipe estimate, `|R| = exp(−(ka)²/2)` with end correction 0.61a.

Rigid and open at the same place are nearly orthogonal (`condQ` ≈ 1.0 at low frequencies, 1.4 at
2 kHz, 2.4 at 4.7 kHz) and need no absorber. They are offered as a pair; the owner chose the absorber
and rigid cap as the first default.

## 3. Analysis

- **`tim.acoustics.transferMatrix`:**
  - condQ is computed with the columns of Q scaled to unit length after the velocity row is scaled
    by Z_c. The scale of each load is arbitrary (generator level, reference microphone).
  - The 'twoLoad' result keeps all its fields.
- **New `tim.app.processTwoLoad(resA, resB, cfg, resA2)`.** From the processed loads it computes:
  - the matrix T and condQ;
  - the anechoic-termination values τ_a, TL, R_a, α_a = 1 − |R_a|² and the dissipation
    1 − |R_a|² − |τ_a|²;
  - the hard-backed values R_h = (T11 − Z_c T21)/(T11 + Z_c T21) and α_h;
  - the thin-element check |Z_c T21|, |T22 − 1| and the series impedance T12;
  - the reciprocity and symmetry errors;
  - the masks: both loads `valid` and condQ ≤ condQMax;
  - the pair checks of decision 6;
  - the A' check (decision 5);
  - the peak levels and the level step (decision 7).
- **One load, symmetric:** `processTwoLoad` with a single load (method 'oneLoadSymmetric') gives
  the same fields, marked as an assumption.
- **Per-load results:** the validity masks of each load are unchanged. Their τ, α_d and TL_τ stay
  masked with a reflecting termination.

## 4. Simulation

- **`tim.app.terminationModel(cfg, load)`** gives the virtual termination (R, x) of a load:
  - **Absorber:** `simulation.Termination` as configured.
  - **Rigid cap:** R = 1.
  - **Open end:** the unflanged-pipe estimate above.
  - **Place:** at the tube end or the joint, from the simulation geometry's M4 and `tubeDrawing`.
- **The session:**
  - `setSimulationTermination(load)` mounts a load in the virtual rig.
  - The two-load sequence swaps the loads in simulation as the calibration moves the microphones.
  - A one-load measurement in simulation uses Load A.

## 5. Procedure and data (`tim.app.runTwoLoad`)

1. A prompt names load A and asks the operator to check that it is mounted; in simulation the rig
   mounts it.
2. Load A is measured, processed with the session's calibration and saved (`..._loadA`).
3. A prompt describes the swap A → B, then load B is measured at the chosen level and saved
   (`..._loadB`).
4. With the repeat on, a prompt describes the swap B → A, and A' is measured and saved
   (`..._loadA2`).
5. The two-load result is computed and saved:
   - folder: `data/<yyyyMMdd_HHmmss>_twoload_<specimen>/`;
   - `twoload.json`: the load folders and their SHA-256, the loads and the limits;
   - `result.mat`, `results.csv` and the figures.
6. **Stop or cancel:** the loads measured so far stay saved and can be paired later.
7. **Opening:** File > Open measurement on a pair folder reprocesses both loads with the window's
   calibration. File > Combine two saved measurements… pairs two load folders.

## 6. Window

- **Control panel:**
  - MEASUREMENT row: Method list and the background-noise button. Same height; the button reads
    "Background noise".
  - The Start button reads "Start two-load measurement" with two loads.
- **Setup > Tube setup:**
  - Termination box above the Geometry table.
  - The 3D model draws the selected load:
    - the absorber, or the empty extension tube;
    - the end cap, or an open end;
    - at the joint: the extension removed, with or without a cap.
  - "Show: Load A | Load B" with two loads.
- **Measurement > Two-load (new):**
  - operator bar with Continue / Abort (as in the Calibration view);
  - the 3D model of the load to mount, the step list, the condQ curve, the A' difference;
  - the summary table: loads, folders, temperature, level, valid lines, checks.
- **Results:** with a two-load or symmetric result:
  - TL shows the transfer-matrix TL;
  - Reflection shows R_a and α_a, and R_h and α_h;
  - Impedance shows T12 with the thin-element check;
  - Validity adds condQ, the reciprocity error and the A' check;
  - each load's own curves stay available.
- **Results > Transfer matrix (new):** |T11|, |T12|/Z_c, Z_c|T21|, |T22| and their phases; det T;
  the symmetry error.
- **Formula tab section 8:** the procedure, condQ with normalised columns, and the hard-backed
  values. "scripts only" is removed.

## 7. Documents

- `user_guide.md`: Method, Tube setup termination, the two-load procedure, the pair folder,
  combining saved measurements.
- `theory.md` section 3B: column-normalised condQ, the hard-backed values, the thin-element check
  of T, the A' check through T.
- `assumptions_and_limitations.md`, `hardware_status.md` (new PENDING items), README (feature
  list, test count), CLAUDE.md (architecture paragraph).

## 8. Tests

- **Analysis:**
  - T of the simulated porous layer against the model's analytic T, for all load pairs;
  - condQ invariant to the column scale;
  - masks with similar loads;
  - the symmetric option on a symmetric specimen;
  - the pair checks;
  - the A' check with a moved specimen.
- **Simulation:** termination presets and the swaps in the session.
- **Procedure:** `runTwoLoad` end to end in simulation, the saved folders, opening a pair folder,
  combining two folders.
- **Window:**
  - Method row, Tube setup termination box and Show toggle;
  - the sequence in a hidden window;
  - remembered loads (not in hidden windows);
  - panel height unchanged;
  - new views drawn in the window and in the saved figures.
- **Full suite** in a batch MATLAB from the worktree (one MATLAB at a time).

## 9. Hardware check (owner present; all PENDING until measured)

1. **Empty 75 mm section,** A = Absorber, B = Rigid cap at tube end, A' on:
   - T equals the air column [cos kd, jZ_c sin kd; j sin kd/Z_c, cos kd];
   - TL ≈ 0 dB and det T ≈ 1;
   - the A' check passes;
   - record condQ against section 2.
2. **Same section with B = Open end at tube end:** T of both pairs agree.
3. **A specimen** (cyl75 or metasil-cell1) with both pairs: T agrees between the pairs, and TL is
   valid where the one-load TL was masked.
4. **Levels:** the peak level of A and B, and the 10 dB warning.

## 10. Open points

- The A' tolerance is drafted from simulation, then set from step 1 of section 9.

## 11. Implementation (2026-10-14)

- **Commits** on `wo-005`: the work order, the analysis and the sequence (`processTwoLoad`,
  `runTwoLoad`, `saveTwoLoad`, `loadTwoLoad`, `describeLoad`, `terminationModel`, the session's
  `setTermination`), then the window and the saved figures, then the documents.
- **Choices made while building** (open to the owner's review):
  - **Background-noise button:** it reads "Background noise" so that it fits beside the Method list.
  - **Saving time:** the data of every load are saved at once. The figures of the loads and of the
    pair folder are drawn after the last load, so the operator does not wait between the loads. In
    the hidden-window test this took about a minute (three loads × 7 figures + 9). Dropping the
    figures of the load folders would halve it.
  - **Calibration termination:** the switching calibration records the absorber as the termination
    of its sweeps (its first prompt asks for it); in simulation the virtual tube gets it.
  - **condQ change for scripts:** `tim.acoustics.transferMatrix` gives other condQ values than in
    1.3.2 (columns of unit length). T itself is unchanged.
  - **Repeat tolerance:** `analysis.repeatTol` = 0.05 is a draft. In the virtual lab tube the median
    difference without any change was 0.004–0.014 (1–2 sweeps), so the real noise sets it at
    step 1 of section 9.
  - **One-load symmetric result:** saved with its measurement (`res.transferMatrix` in
    `result.mat`). File > Open measurement shows it again.
  - **Combine:** File > Combine two saved measurements (two loads)… also pairs folders saved before
    1.4.0; their termination is then "not recorded".
- **Not built:**
  - the material properties of a homogeneous layer from T (k_s, Z_s; ASTM E2611);
  - the two-source method;
  - a least-squares T from three loads.
