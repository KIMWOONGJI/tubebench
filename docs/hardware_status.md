# Hardware verification status

Legend: **HW-VERIFIED** = exercised against the real instrument in this lab;
**SW-VERIFIED** = verified only with mocks / simulation / recorded fixtures;
**PENDING** = needs the physical test described in `validation_procedure.md`.

Hardware sessions so far, all from this PC via the instruments' link-local Ethernet addresses; up to
2026-10-10 with software 1.1.0 (before the instrument interface of WO-001), on 2026-10-12 with the
1.2.0 code (branch `wo-001` at commit 2726e1c):

* **2026-10-08**: identification, LAN-XI recorder cycle and bench tests without the tube; until
  21:01 the generator output was never switched on. From 21:01 the 33220A drove the loudspeaker
  directly, without an amplifier, at up to 0.5 Vpk (section "Bench test with excitation").
* **2026-10-09 and 2026-10-10**: in the tube - two switching calibrations, each with its automatic
  empty-tube check, and five swept-sine measurements at 0.1 Vpk (0.2 Vpp), direct drive (section
  "In-tube sessions 2026-10-09 / 2026-10-10").
* **2026-10-12**: the owner's hardware check of the WO-001 instrument interface (steps 1-10, all
  passed), in the tube with the empty 75 mm section, direct drive, 0.025-0.5 Vpk; it found that the
  33220A drops an idle socket connection now and then (section "Hardware check of the refactored
  drivers"). In the afternoon, the owner's check of 1.2.1 (WO-003, steps 1-4, all passed; section
  "Hardware check of 1.2.1"), run from the worktree `tubebench-wo003`.

Folder names: on 2026-10-14 the one-load measurement folders saved before 1.4.0 were renamed to
the 1.4.0 naming. The method was added after the time stamp, for example `20261009_192503_sweep`
became `20261009_192503_oneload_sweep`. The specimen "cyl75" is the empty 75 mm section (owner), so
its two folders now end in `empty75`; their files still name it "cyl75". This document uses the
new names. The list of old and new names is in `data/RENAMED_2026-10-14.txt`. No file inside a
folder was changed.

## Instruments found

| Instrument | Identification (read from the device) |
|---|---|
| Keysight/Agilent 33220A | `Agilent Technologies,33220A,MY44032054,2.02-2.02-22-2` (firmware 2.02), output OFF, error queue empty |
| HBK LAN-XI | Type 3676-B-040, serial 110283, firmware **2.10.0.610**, hardware 4.0.0.0, front panel UA-2100-040 |

LAN-XI capabilities reported by `/rest/rec/module/info`:
* sample rates 65536, 32768, 16384, 8192, 4096 S/s
* ranges "1 Vpeak", "10 Vpeak"
* high-pass filters DC, 0.1 Hz 10%, 0.7 Hz, 1.0 Hz 10%, 7.0 Hz, 22.4 Hz, Intensity
* connectors **BNC and LEMO** (`ConnectorSelect` in the channel setup; the default is BNC)
* destinations sd / socket / multiSocket / socketUdp; PTP "Locked" (stand-alone)

## Function status

| Function | Status | Evidence / note |
|---|---|---|
| 33220A TCP socket, `*IDN?`, `SYST:ERR?`, `OUTP?` | HW-VERIFIED | read-only queries |
| 33220A configure sine/sweep/noise, `*TRG`, `*OPC?`, `OUTP ON/OFF` | HW-VERIFIED (sweep, sine); noise SW-VERIFIED | sine: bench 2026-10-08 (B2, stepped B5); sweep: in-tube 2026-10-09/10 and 2026-10-12 (SCPI log of the check: configuration, read-back, `OUTP ON`, `*TRG`, `*OPC?`, `OUTP OFF` per repetition). Noise (`FUNC NOIS`) not run on the instrument |
| 33220A amplitude read-back safety check | HW-VERIFIED (pass path) | 2026-10-12: `VOLT?` read back before every `OUTP ON` (SCPI log); the refusal path is SW-VERIFIED only |
| 33220A load setting at the amplifier input (`OUTP:LOAD <ohms>` 1-10000 and its read-back `OUTP:LOAD?`; `generator.maxVpp` as open-circuit voltage; WO-004, 1.3.0) | **HW-VERIFIED** (load setting, output OFF; no measurement through an amplifier yet) | 2026-10-13, owner present, `docs/workorder_excitation_drive.md` section 5: Connect with an amplifier chosen and Amp input 600 Ω passed, so the driver's read-back `OUTP:LOAD?` = 600 (it stops the Connect otherwise), and the generator's display showed 600 Ω; after Disconnect, direct drive and Connect again the generator answered `OUTP:LOAD?` 9.9E37 (INF), `OUTP?` 0, `SYST:ERR?` +0 "No error". Step 3 (a measurement through an amplifier, optional) not done. Software: `TestInstruments/generatorAtTheAmplifierInput`; direct drive sends the same commands as before (bus-traffic fixtures unchanged) |
| Drive check of the window (loudspeaker power at the nominal impedance, OK / near / above; the criterion of the largest level) | SW-VERIFIED | `TestConfiguration/driveStatesAndLimits`, `TestGui/excitationChainControls`; computed only (no instrument I/O) |
| 33220A socket left idle | **known issue** of the instrument (1.1.0 and 1.2.0); **handled since 1.2.1: HW-VERIFIED** (section "Hardware check of 1.2.1") | 2026-10-12: after 5-45 min without traffic the 33220A had dropped the TCP connection three times without the PC noticing; the next measurement then failed on its first command ("connection forcibly closed by the remote host", then "must be connected to remote server") before any output was armed. Not every idle period: a connection was still alive after 18 min without traffic (12:10–12:29), another 9.5 min after a measurement (an `OUTP?` at 13:08:37). Workaround before 1.2.1: Disconnect → Connect. Since 1.2.1 a connection idle for more than 30 s is replaced before use, and a failed connection check re-opens it (section "Hardware check of the refactored drivers", observation 1) |
| SCPI transport: a late reply after a query time-out is discarded; the next query resynchronises with `*IDN?` (audit fix 2026-10-11) | SW-VERIFIED | local fake instrument on 127.0.0.1 (`TestInstruments/scpiLateReplyIsNotTakenAsTheNextAnswer`); not exercised on the 33220A (a time-out needs a slow or interrupted link) |
| LAN-XI: a fault while a recording starts (POST, its reply lost, or the RecorderRecording wait) closes the stream and stops the recording (audit fix 2026-10-11) | SW-VERIFIED | mock fault injection (`TestInstruments/lanxiStartFailureReleasesTheStream`); PENDING on hardware |
| LAN-XI REST client (GET/PUT/POST, HTTP 403 handling) | HW-VERIFIED | `PUT /create` in Idle → `403 "Cannot create recording in module state Idle"` |
| LAN-XI open → create → TEDS detect → setup → stream → stop → finish → close | HW-VERIFIED | full cycle, module returned to Idle |
| Recovery from an unexpected state (`shutdown`) | HW-VERIFIED | after a client-side timeout the module was in RecorderStreaming and was returned to Idle |
| `PUT /channels/input` duration | HW-VERIFIED | **> 10 s** on this module, so the timeout was raised to 60 s |
| Binary stream decoding (SignalData, Interpretation, DataQuality) | HW-VERIFIED | 2 s at 16384 S/s × 4 ch: 128 SignalData, 4 Interpretation, 4 DataQuality messages, 0 corrupt bytes, 0 timestamp gaps; ScaleFactor 11.885 = 10 V × 10^(1.5/20); unit "V"; bit-identical re-decode with random chunking. Fixture: `tests/fixtures/lanxi_stream_3676_noise_16k.*` |
| Data unit / single application of sensitivity | HW-VERIFIED | stream unit "V" with the default transducer |
| DataQuality flag reporting | HW-VERIFIED | flag 8 (INVALID: cable fault / CCLD / overload) reported on all 4 channels (see below) |
| TEDS reading | HW-VERIFIED (all four channels) | bench 2026-10-08 18:02: ch3 no TEDS; since 20:41 that day (operator intervention) TEDS on all four inputs, also in the tube 2026-10-09/10 and on 2026-10-12 (ch1 11.19, ch2 10.96, ch3 11.87, ch4 10.43 mV/Pa) |
| Microphone signals (4957 via CCLD) | HW-VERIFIED (all four channels) | the ch3 fault of 2026-10-08 18:02-18:42 (LAN-XI input 3, CCLD loop) has not recurred since 20:41 that day; 2026-10-12: integrity OK and signal check OK on all four channels in every measurement |
| 33220A sweep/sine configuration + read-back, safety refusals | HW-VERIFIED (output OFF) | bench 2026-10-08: 80–5500 Hz LOG 5 s 0.05 Vpp read back; `outputOn` refused when not armed; 1 Vpp refused with maxVpp 0.2 |
| BNC/LEMO `ConnectorSelect` | observed: no difference | identical TEDS/signals with BNC and LEMO selected (microphones on the connectors in use) |
| Channel → port mapping | **PENDING** | `tim.val.channelIdentification` |
| Excitation + acquisition (sweep timing, trigger latency) | HW-VERIFIED (bench and in-tube sweeps); formal test **PENDING** | bench B3 2026-10-08: sweep start, duration −0.05 %, ≈ 0.26 s from the software trigger to the acoustic start; the 20 sweeps of the five in-tube measurements of 2026-10-09/10: excitation detected in every repetition, sweep-law duration error −0.01 … +0.11 %. The formal `tim.val.sweepTimingTest` (H4) has not been run |
| Single-frequency test (Test B) | **PENDING** | bench B2 2026-10-08 (1 kHz sine, 0.1 and 0.5 Vpk: SNR and block scatter, section below) covers the excitation path; the formal `tim.val.testB_singleFrequency` (H5) has not been run |
| Switching calibration on hardware (Test C) | **PENDING** (consistency) | two switching calibrations made in the tube with the empty 75 mm section (CAL-20261009-191631, CAL-20261010-212544; section "In-tube sessions"); the consistency criteria of Test C (`tim.val.testC_calibrationConsistency`) not evaluated |
| Rigid termination (Test D), empty tube (Test E), stepped vs sweep (Test G) | **PENDING** | the automatic empty-tube check of both calibrations passed (section "In-tube sessions"); Test D, the repeated Test E after it (H7) and Test G not run; the geometry is still the CAD design (calipers pending) |
| GUI | HW-VERIFIED (measurement workflow) | used on the instruments 2026-10-09/10 (1.1.0) and in the hardware check of 2026-10-12 (connect, swept-sine measurement, Stop, closing, Open measurement, Reprocess); calibration in the window: 1.1.0 only. Every view: simulation and hidden-window tests |
| Session gates that exist only in hardware mode: amplifier gain required (`tim:session:gainRequired`), excitation confirmation in the command window (scripts), settle wait of the inputs | HW-VERIFIED in the window (confirmation, settling); the rest SW-VERIFIED | `TestSessionHardwareMode` (test-only drivers on the protocol mocks, no network I/O; owner decision 2026-10-11). 2026-10-12: the confirmation dialog appeared before the first excitation of a setting (not again for the same setting, by design: `MeasurementSession.ConfirmedExcitation`), and the 3.0 s settle wait ran at every Connect. Gain required: not exercised (direct drive) |
| Swept-sine analysis of 2026-10-11 (owner decisions): frequency lines centred on their frequency; an end of a sweep without the margin outside the band gets another window edge (limits 91 / 4952 Hz for 120–4500 Hz, also in the configuration check) | HW-VERIFIED (2026-10-12) | simulation (`TestDsp`, `TestConfiguration`, `TestPlotsMeasurement`); the five lab folders and both lab calibrations reprocessed read-only in memory (gate rule bit-identical, centred lines change the results slightly: section "After the merge"). On real records: 80–5500 Hz keeps the gate at both ends, 120–4500 Hz takes the fallback at both ends (hardware check steps 5 and 9) |
| File > Open measurement… offers the recorded microphone mapping for Reprocess; one close request during it closes the window (its questions count as cancelled) | HW-VERIFIED (no-question case); the mapping question SW-VERIFIED | 2026-10-12, hardware check step 10: the measurement of step 5 opened without a question, and Reprocess gave its saved results bit for bit. The question itself (a configuration with another mapping) and closing during it: hidden-window tests (`TestGui`) |
| Instrument interface of 1.2.0 (WO-001: drivers through the registry, configuration by driver name, identity display in the window; review fixes of 2026-10-11) | HW-VERIFIED (2026-10-12) | the owner's hardware check (WO-001 §0.3), steps 1-10 passed; contract tests, bus-traffic fixtures and hidden-window tests in simulation. Section "Hardware check of the refactored drivers" below |
| Two-load transfer matrix (WO-005, 1.4.0): Method Two loads, the terminations of Tube setup, A → B → A′ with the operator bar, every load saved, the pair folder, condQ with columns of unit length, the repeat of load A through T, the level of load B | HW-VERIFIED (2026-11-02, a specimen against a 3D FE model) / SW-VERIFIED | **Hardware, 2026-11-02** (1.4.1, pair folder `20261102_154635_twoload_ventsil-m8-cell1`): a 3D-printed resonator cell, A = absorber at the tube end, B = rigid cap at the joint, A′. 1929 of 2301 lines valid in both loads, all with condQ ≤ 10; repeat of load A 0.03 (median, limit 0.05: nothing moved); peak level of B 6.6 dB above A (no warning). TL from T peaks at 376 Hz with 12.87 dB (data); the owner's 3D finite-element model with thermoviscous losses gives 377 Hz and 13.4 dB, the other resonances within 3 % in frequency, the measurement up to 2.4 dB lower above 2 kHz (owner's comparison, figure in the README and on the project page). The one-load τ of load A (\|R_term\| 0.48–0.53 at 380–420 Hz) peaks at 370 Hz with 10.97 dB and is masked on every line (termination not anechoic). \|det T − 1\| > 0.1 on 300 valid lines (report only). The owner counts this comparison as the hardware verification of the method (2026-11-03). Not done from `docs/workorder_two_load.md` section 9: steps 1–2 (empty 75 mm section against the air column, open end) were not repeated after the runs of 2026-10-14 (work order section 12), and step 3 used one pair of loads only. **Simulation:** `TestTwoLoad` (analytic tube model: T, τ_a, R_a, R_h for a porous layer and an asymmetric specimen; condQ independent of the scale of a load; similar loads masked; pair checks; repeat of load A; the sequence in the virtual tube), `TestGuiTwoLoad` (hidden window), `TestTube3D/terminationsDrawn` |
| Termination recorded with every measurement (`metadata.termination`, 1.4.0) | SW-VERIFIED | as selected in Setup > Tube setup (the calibration records the absorber); a record, not a measurement of the termination |

## Observation from the first hardware acquisition (IMPORTANT)

With CCLD on, the BNC connector selected (the module default), range 10 Vpeak and the 0.7 Hz
high-pass, all four channels showed:

* DataQuality flag **8 (INVALID)** from the first sample, on all channels;
* an identical slowly decaying offset of about −0.97 V → −0.89 V over 2 s, and ~49 µV rms noise
  (100–5000 Hz) on every channel;
* no TEDS on any channel.

All four channels behaving identically is the typical signature of **no transducer connected to
the selected input (open CCLD loop / cable fault)**. Possible causes, to be checked by the operator:

1. The microphones are not connected (yet).
2. The microphones are connected to the **LEMO** inputs while the software selected **BNC**. Set
   `"daq": {"lanxi": {"connector": "LEMO"}}` in `config/user_config.json` (in a file of the older
   layout, as the lab file still is: `"lanxi": {"connector": "LEMO"}`).
3. Cable or adaptor fault.

No change was made to the instrument configuration beyond the temporary recorder session, which
was closed (module back in Idle).

## Bench test 2026-10-08 18:02 (microphones connected, not in the tube)

Placeholder geometry in `config/user_config.json` (only bore 29 mm and spacing 29 mm are real).
No excitation. Result: ch1, ch2, ch4 OK (TEDS + clean signal). **ch3 faulty**: no TEDS and
INVALID (cable fault / CCLD) with a DC offset. The earlier "all channels INVALID" observation was
caused by unconnected microphones. To localise the ch3 fault, swap the ch3 cable or microphone
with a working channel (`examples/bench_test_no_tube.m`, section B0).

### ch3 fault localisation

* 18:28: microphone of ch3 reconnected, fault unchanged.
* 18:37: microphones of ch3 and ch4 interchanged, cables unchanged. The former ch3 microphone
  (4957 s/n 3342022, TEDS 11.187 mV/Pa) works normally on ch4, and the former ch4 microphone
  (s/n 3342023) fails on ch3. **Microphone OK; the fault is in cable 3 or LAN-XI input 3.**
  Next step: interchange the LAN-XI ends of cables 3 and 4.
* 18:40: cables + microphones of inputs 3 and 4 interchanged at the LAN-XI. Input 3 still fails
  (with the good microphone s/n 3342022 and cable 4); input 4 works with cable 3 and s/n 3342023.
  **Cable 3 and both microphones OK; the fault is LAN-XI INPUT 3.**
* 18:42: `/rest/rec/onchange` → `recordingStatus.channelStatus`: input 3 `cf = now` (cable fault),
  `anol = none`, `cmol = none`. All other inputs report none. With CCLD switched off on input 3,
  no fault flag is raised (CCLD-based detection is inactive), but the input shows about 1.08 V DC
  and about 350 mV rms of unstable signal. Conclusion: the CCLD loop of input 3 is not working.
  Suspects: input 3 connector/contact or fitted adaptor, or the input 3 CCLD hardware.
  Recommended actions: inspect/clean the connector, swap the adaptor, try the LEMO connector of
  input 3, otherwise HBK service (3676-B-040, s/n 110283, fw 2.10.0.610).
* 20:41 (after operator intervention on the set-up): **all four inputs OK**. TEDS on every
  channel (ch1 3350978, ch2 3342023, ch3 3342022, ch4 3350977), `cf/anol/cmol = none`, integrity
  OK, background 47–55 dB SPL. DC offset of about −1 V on all channels shortly after CCLD
  switch-on (high-pass settling, harmless). At the same time the 33220A did not answer ping or
  TCP 5025 (power or LAN cable to be checked).

## Bench test with excitation 2026-10-08 21:01–21:15 (no tube, no amplifier)

Set-up: 8 Ω / 25 W loudspeaker driven **directly** from the 33220A Output (50 Ω source;
current ≤ Vpk/58 Ω). Microphones lying loosely around the loudspeaker (not bundled, not in a tube).
Room background 54–64 dB SPL (100–5000 Hz). Data: `data/bench_20261008_211005/`.

| Step | Result | Status |
|---|---|---|
| B0 Test A | 4 channels TEDS + integrity OK | HW-VERIFIED |
| B1 channel identification | not conclusive (the table was tapped, which excites every microphone). Procedure changed to blowing onto one microphone at a time with a countdown window | PENDING |
| B2 1 kHz sine, 0.1 Vpk (1.7 mA) | tone 36–42 dB SPL, narrow-band SNR 17–25 dB | HW-VERIFIED (excitation path) |
| B2 1 kHz sine, 0.5 Vpk (8.6 mA) | tone 51–58 dB SPL, SNR 32–40 dB, block scatter 0.11–0.24 dB / 0.8–1.6° | HW-VERIFIED |
| Generator vs LAN-XI clock | about −100 ppm (two independent estimates); irrelevant for the ratio method | observed |
| B3 sweep trigger/timing (5 s, 0.5 Vpk) | sweep start 1.261 s, duration 4.997 s (−0.05 %), identical on all channels within 0.1 ms; ≈0.26 s from software trigger to acoustic start; margins 1.26 s / 0.94 s | HW-VERIFIED |
| B4 sweep relative responses (4 × 5 s, 0.5 Vpk) | band SNR ≤ 0 dB below 1 kHz, 13–20 dB at 1–3 kHz (free field, room noise) | HW-VERIFIED (method); level too low for broadband use in free air |
| B5 stepped vs sweep | agreement 0.01–0.5 dB / 0.2–5.6° where sweep SNR ≥ 11 dB (1.3–2.3 kHz); deviations grow as sweep SNR drops (≤ 0 dB below 800 Hz) | HW-VERIFIED (consistent with SNR) |
| Config I for B6 (2 × 20 s, 1.0 Vpk) | band SNR 17–25 dB at 1–3 kHz, 3–11 dB below 300 Hz | recorded |
| B6 switching practice | skipped (postponed to the in-tube calibration) | PENDING |

Software changes prompted by the bench test: narrow-band SNR for the sine estimator; matched-filter
sweep-law estimate (the ridge fit fails at low SNR); −40 dB floor on the reported sweep SNR;
amplifier record and operator confirmation; stepped-sine scheduler without drift.

Microphone ↔ channel assignment at the end of the session (TEDS): ch1 3342023, ch2 3350978,
ch3 3342022, ch4 3350977. **Enter the final mapping in `config/user_config.json → mics` before
measuring in the tube.**

## In-tube sessions 2026-10-09 / 2026-10-10 (software 1.1.0)

Recorded from the saved folders and calibration files (read only). Every run: hardware mode, the
33220A driving the loudspeaker directly (no amplifier), 0.2 Vpp (0.1 Vpk), swept sine 5 s × 4
repetitions, LAN-XI 16384 S/s, 10 Vpeak, 0.7 Hz, CCLD, BNC; TEDS on all four channels (ch1 3342022,
ch2 3342023, ch3 3350977, ch4 3350978); T entered 20 °C (not measured); geometry = CAD design
values (s1 29, L1 41, d 75, L2 41, s2 29 mm, not yet checked with calipers).

| Time | Run | Result |
|---|---|---|
| 10-09 19:16 | switching calibration `CAL-20261009-191631`, empty 75 mm section, sweep 80–5500 Hz | C_k valid on 88–90 % of the lines 120–4500 Hz; automatic empty-tube check **passed**: \|τ\| error 0.007, τ phase error 1.35° rms, R consistency 0.0196 (limit 0.02), 1869 lines |
| 10-09 19:20 | `data/20261009_192503_oneload_sweep`, empty 75 mm section, 80–5500 Hz | integrity OK; 1860 of 2191 lines valid (R: 1918); termination not anechoic (τ, TL masked); evaluated in theory.md ("First lab data") |
| 10-09 20:15 | `data/20261009_201658_oneload_sweep`, 80–5500 Hz | integrity OK; d entered as 53.3 mm (M2–M3 135.3 mm instead of 157 mm), so the calibration's empty-tube check does not apply (warning in the result); what was mounted is not recorded in the folder |
| 10-10 21:26 | switching calibration `CAL-20261010-212544`, empty 75 mm section, sweep 80–5500 Hz | C_k valid on 96–97 % of the lines; automatic empty-tube check **passed**: \|τ\| error 0.007, τ phase error 0.80° rms, R consistency 0.012, 2031 lines |
| 10-10 21:34 | `data/20261010_234024_oneload_sweep` (saved 23:40), no specimen name, d = 75 mm, 80–5500 Hz | integrity OK; 2096 of 2191 lines valid (R: 2125) |
| 10-10 23:43 | `data/20261010_234354_oneload_sweep_empty75`, specimen "cyl75" (the empty 75 mm section, = empty75), 80–7300 Hz | integrity OK; 2045 lines valid (R: 2104) |
| 10-10 23:52 | `data/20261010_235332_oneload_sweep_metasil-cell1`, specimen "metasil-cell1", d entered as 53.3 mm, 80–7300 Hz | integrity OK; 1591 lines valid (R: 1858); same port-distance warning as 10-09 20:15 |

These runs exercised the excitation, acquisition, calibration and processing chain on the real
instruments. They are not the formal Tests C, D, E (H7) or G: the consistency of the calibration
(repeated configuration I) was not evaluated, the termination is not anechoic, and the geometry
and the temperature have not been measured. Those rows stay **PENDING** above.

## Hardware check of the refactored drivers (WO-001), 2026-10-12: passed

Since 2026-10-11 the 33220A and the LAN-XI are driven through the instrument contract and the
driver registry (`docs/instrument_interface.md`, `docs/workorder_instrument_interface.md`). Before
the check this was software-verified only: the full test suite in simulation (337 tests in 22
classes, `run_tests()` 337 / 337 on 2026-10-11 at commit b05a7cf), the contract tests of every driver, and the
bus-traffic tests, which show that a simulated session sends the same SCPI commands and REST
requests as the code before WO-001 (three documented changes of order on fault paths,
approved by the owner on 2026-10-11: closing the window inside a sweep, a Stop during the LAN-XI
connect step, and D24 - on a Stop or an error of the acquisition the generator output is switched
off before the LAN-XI stop request, not after it).
The same branch changes three things the check below looks at as well (owner decisions of
2026-10-11, simulation only so far): **D24** (above); the **sweep gate** - a sweep that does not
reach far enough beyond the analysis band is analysed with another window edge at that end (start
at or below 91 Hz and stop at or above 4952 Hz for the band 120–4500 Hz at Δf = 2 Hz; the lab
sweep 80–5500 Hz keeps the gate at both ends, and its frequency lines are now centred on their
frequency, `docs/theory.md` section 4); and the **recorded microphone mapping** that File > Open
measurement… offers for Reprocess when the configuration's mapping differs.
The owner's check (WO-001 §0.3), each step only with the owner present; at the first surprise:
output off at the generator, close the window, report. It was run on 2026-10-12 with the code of
branch `wo-001` at commit 2726e1c (results after the list):

1. **Reconnect** the 33220A (LAN, 169.254.2.20:5025) and the LAN-XI 3676 (169.254.64.156) as on
   2026-10-08, no address or firmware change; the microphones on their channels; amplifier at
   minimum gain (or direct drive), loudspeaker connected only for steps 5-9. Check out `wo-001`;
   `config/user_config.json` stays as it is (D7: it is rewritten in the new layout only after this
   check). Expected: both instruments answer as before; the 33220A output LED off.
2. **The lab file loads unchanged**: `cfg = tim.app.loadConfig('config/user_config.json')` gives
   no warning; `cfg.generator.driver` `'keysight33220a'`, `cfg.daq.driver` `'lanxi'`,
   `cfg.daq.lanxi.connector` `'BNC'`, `cfg.generator.maxVpp` 2; `tim.app.validateConfig(cfg)` has
   no "Swept sine: let the sweep start at or below 91 Hz …" line (the lab sweep 80–5500 Hz keeps
   the margin of the sweep gate).
3. **Connect and identify with the output off** (script, nothing is switched on):
   `s = tim.app.MeasurementSession(cfg); s.connect(); disp(s.Gen.identity()); disp(s.Daq.identity()); s.Gen.isOutputOn(1)`,
   then `s.close()`. Expected: 33220A `MY44032054`, firmware 2.02; LAN-XI 3676-B-040, s/n 110283,
   firmware 2.10.0.610; `isOutputOn(1)` false and the output LED off; after `close()` the
   generator front panel is in local mode (the 33220A shows no "Rmt" annunciator for a LAN socket
   session: check that a front-panel key such as Utility responds), and a new session (`s2 = tim.app.MeasurementSession(cfg);
   s2.connect(); s2.close()`) prints no "[LAN-XI] Module not in state Idle" line (the module was
   left in Idle); no error.
4. **The window** (`tubebench`, hardware): before Connect "In use" shows "Keysight/Agilent 33220A
   function generator" and "HBK LAN-XI module (Open API)", the lamps "Generator" and "LAN-XI";
   Connect runs the checklist (function generator, LAN-XI module (REST), recorder state Idle, open
   recorder, TEDS, channel setup - more than 10 s -, sensitivities, settling, signal check: ch3
   may fail, the known fault) with the identities of step 3; afterwards "In use" reads
   "Generator: 33220A s/n MY44032054" and "LAN-XI: 3676-B-040 s/n 110283" without "(simulated)",
   and Setup > Connection lists vendor, model, serial number and firmware of both. Output LED off.
5. **A short measurement at an approved level**: the owner states the level, at most the
   configured default 0.2 Vpp (EXCITATION amplitude ≤ 0.1 Vpk; e.g. 0.05 Vpp first), swept sine
   80–5500 Hz, one repetition, the amplifier record entered; answer the excitation confirmation
   only after the owner agreed (it is asked before the first excitation of a setting, not again
   for an unchanged setting). Expected: the output LED is on only during the sweep; the sweep
   lies inside the record on ch1, ch2, ch4; no integrity error apart from ch3; the output LED off
   afterwards. **Sweep gate at both ends**: no "Sweep … too close to the analysis band" warning in
   the message pane; in Measurement > Time signals the grey parts lie before and after the sweep
   and the header note reads "Grey: not analysed (before … s and after … s: generator output
   on/off, start-frequency tone)" (`res.diagnostics.excitation(1).gateEnds` = `{'gate', 'gate'}`).
6. **Stop during a measurement**: the same level, a longer sweep (e.g. 5 s, 4 repetitions); press
   Stop in the middle. Expected (**D24**): the output LED goes off at once - the output is switched
   off before the LAN-XI module is stopped; the message pane shows "Error during swept sine,
   repetition k: Measurement stopped by user. Generator output commanded off (not read back).
   Partial data saved to …" and then "Measurement stopped by the operator. Generator output off
   (confirmed)."; the partial data are kept; the next measurement works without reconnecting.
7. **Output-off read-back**: after steps 5 and 6 the status line shows no "Generator output not
   confirmed off"; the 33220A shows the output off (LED) - the read-back (`OUTP?`) and the
   instrument agree.
8. **Closing**: close the window while connected, once idle and once during a measurement (one
   close request). Expected: during the measurement the running repetition stops at once (output
   LED off, "Error during swept sine, repetition k: Measurement stopped by user …" as in step 6),
   then the closing window lists "Generator output off (confirmed)" and "Instruments
   disconnected"; the output LED stays off; the generator is back in local mode; at the next
   Connect the checklist step "LAN-XI recorder state Idle" reads "Idle" (not "was ... returned
   to Idle").
9. **Sweep gate at an end without the margin** (optional; the same approved level, one
   repetition): EXCITATION swept sine 120–4500 Hz (the analysis band itself). Expected: at the
   first Start with this setting the message pane shows "CHECK: Swept sine: let the sweep start at
   or below 91 Hz and stop at or above 4952 Hz …" (a CHECK text is logged once until it changes);
   after the measurement the warning "Sweep 120-4500 Hz too close to the
   analysis band for the sweep gate: the analysis window starts at the detected excitation …; the
   window is extended past the end of the sweep by the gate's ring-down margin …"; the Time
   signals note says that the analysed part includes the output-on transient and the
   start-frequency tone and continues past the sweep end by the ring-down margin; `gateEnds` =
   `{'detected start', 'ring-down margin'}`. Then set the sweep back to 80–5500 Hz. This is the
   first run of the fallback on real records (lab trigger latency 0.13–0.28 s); simulation only so
   far.
10. **Open measurement and the microphone mapping**: save the measurement of step 5 (a new folder
    under `data/`), then File > Open measurement… on that folder. Expected: no mapping question
    (recorded and configured mapping both ch1 M1, ch2 M2, ch3 M3, ch4 M4); the message pane ends
    with "Reprocess uses the IMPEDANCE TUBE fields and the active calibration (…)" without a
    mapping clause; Reprocess gives the saved results again (do not save). Optional, without the
    instruments: File > Load configuration… (it disconnects them) with a copy of the lab file
    **outside** `config/` (e.g. in `%TEMP%`) whose `mics` swap ch1 and ch2, open the folder again:
    the question "Use the recorded mapping" / "Keep the configuration's mapping" appears; "Use the
    recorded mapping" and Reprocess give the saved results; open the folder once more and close
    the window while the question is open - one close request closes it (the question counts as
    cancelled). Start the program again with `config/user_config.json`.

Set-up on 2026-10-12: empty 75 mm specimen section; direct drive (no amplifier), loudspeaker 8 Ω;
the level approved by the owner for the check: 0.025 Vpk (0.05 Vpp). The owner also ran some
measurements at 0.1, 0.25 and 0.5 Vpk (0.2, 0.5, 1 Vpp; estimated loudspeaker power at most
0.3 mW against the 1 W limit). The SCPI and REST logs of the sessions were read in MATLAB, and the
TCP state of the generator connection was logged from Windows.

| Step | Status | Date, result |
|---|---|---|
| 1-2 reconnect, lab file loads | **HW-VERIFIED** | 2026-10-12 12:0x: ping 1.5 / 6 ms, LAN-XI REST 200 in Idle; `loadConfig` without a warning (`keysight33220a`, `lanxi`, BNC, maxVpp 2, sweep 80–5500 Hz), `validateConfig` without a line (also with 'instruments') |
| 3 connect and identify, output off | **HW-VERIFIED** | 12:04-12:06: identities as expected; `isOutputOn` false, output LED off during a 10 s hold (owner); a second connect / close without "not in state Idle", module in Idle afterwards; front panel responds after close (no "Rmt" annunciator on a LAN socket) |
| 4 window: instruments in use, identities | **HW-VERIFIED** | 12:10: "In use" before Connect (owner); "Connected - all checks passed", 10 checklist steps, TEDS on 4 of 4, channel setup 16.3 s, signal check OK on all four channels; "In use" and the Instruments table show model, serial and firmware without "(simulated)" |
| 5 short measurement at an approved level (≤ 0.2 Vpp), sweep gate at both ends | **HW-VERIFIED** | 12:29, 0.05 Vpp, `data/20261012_123025_oneload_sweep_hwcheck-step5`: integrity OK on all four channels; `gateEnds` {gate, gate}, no warning; sweep found at 1.489 s, 5.006 s long (matched peak ratio 713); output off about 0.09 s after the sweep end, the start-frequency tone in between outside the gate; Time signals note "Grey: not analysed (before 1.49 s and after 6.49 s …)"; LED on only during the sweep (owner) |
| 6 Stop during a measurement (D24: output off before the LAN-XI stop) | **HW-VERIFIED** | 12:38, Stop in repetition 2: SCPI `OUTP OFF` 12:38:12.267, REST `PUT /rest/rec/measurements/stop` 12:38:12.710 (D24 order); the messages as expected, `OUTP?` 0, partial data in `data/emergency/`; LED off at once (owner). 14:02:47 Stop, 14:03:34 the next measurement started without reconnecting and ran normally |
| 7 output-off read-back | **HW-VERIFIED** | no "not confirmed off" after a normal end or a Stop; `OUTP?` 0 and the LED off. (The "not confirmed off" messages of observation 1 came from a dropped connection, not from a read-back mismatch.) |
| 8 closing (idle, during a measurement) | **HW-VERIFIED** | 14:04:57 closed while idle (the PC closed the generator socket); 14:07:05 closed in repetition 2: "Closing: window close requested while busy - STOP requested first.", the repetition stopped at once (partial data 14:07:06). At the next Connect (14:08:40) the output read back off and the checklist step "LAN-XI recorder state Idle" read "Idle". The session log in the MATLAB command window shows both closings: "Closing: Generator output off (confirmed)." and "Closing: Instruments disconnected." (14:04:56-59 and 14:07:08-09). At the idle closing `PUT /rest/rec/finish` timed out after the 2 s closing time-out ("shutdown step in RecorderStreaming failed"); the shutdown loop went on and the module was in Idle at the next Connect |
| 9 sweep gate at an end without the margin (optional) | **HW-VERIFIED** | 12:43 / 12:53-12:59, 120–4500 Hz, 4 repetitions, 0.025-0.5 Vpk: the CHECK line at the first Start of the setting; `gateEnds` {detected start, ring-down margin} in every repetition; the warning as expected; integrity OK. First run of the fallback on real records |
| 10 Open measurement and the microphone mapping | **HW-VERIFIED** | 14:08 (window not connected): no mapping question, the message pane ends with "Reprocess uses the IMPEDANCE TUBE fields and the active calibration (none - results not valid)."; Reprocess (14:12) reproduces the saved results bit for bit (H, R, R_term, Z_c, k, τ, masks, `gateEnds`). The optional part (another mapping) was not run |

Every step passed on the real instruments: version 1.2.0 (`tim.app.softwareVersion`) and the merge
of `wo-001` into `main` followed on 2026-10-12.

**Observations of the check**

1. **The 33220A drops an idle socket connection now and then (known issue, also in 1.1.0).** Three
   times the first Start after an idle period failed on the first SCPI commands (12:36:55 after
   about 7 min, 12:43:04 after 5 min, 13:52:10 after 43 min). The MATLAB command window showed
   "현재 연결은 원격 호스트에 의해 강제로 끊겼습니다" (WSAECONNRESET: the instrument answered the
   first command with a reset) and the window "Error (measurement): … 객체는 remote server에 연결되어야
   합니다", "The generator output could not be confirmed off". The output had not been armed (the
   failure came before the excitation confirmation); Disconnect → Connect restored the connection.
   While idle, Windows showed the connection as established and logged no adapter, Wi-Fi or standby
   event; ping and the Ethernet link stayed up; the ARP entry of 169.254.2.20 is the 33220A's own
   MAC (00-30-D3-09-56-16, from its web page), so no address conflict. A fourth drop confirmed that
   the instrument drops the connection **silently**: the Windows TCP state, logged every 0.5 s,
   showed the connection made at 14:08:40 as established without a break until 14:33:00, when the
   owner pressed Start, and then gone - no FIN, no CloseWait; an `OUTP?` had still been answered at
   14:18:42, so the drop happened within 14 min of idle. The PC cannot see such a drop without
   sending something. Not every idle period: a connection was alive after 18 min, another 9.5 and
   10 min after its last traffic.
   The transport (`ScpiTcpTransport`, `tcpclient`) is unchanged since 1.1.0, and the owner had seen
   the same before. Fix planned for 1.2.1: a check of the connection before every measurement or
   calibration with an automatic reconnect (same serial number, output off, `OUTP:LOAD`), an English
   message and the lamp (built in 1.2.1, branch `wo-003`; the stack trace MATLAB's tcpclient prints
   in the command window on the reset cannot be suppressed - harmless). At 15:1x the owner set the 33220A
   from DHCP + Auto IP (no DHCP server on this network) to a static IP with the same address
   (169.254.2.20 / 255.255.0.0); an idle probe on one socket (`*IDN?` after 1, 2, 5, 10, 15 and 30 min
   of idle) showed that it does not: the connection dropped between 15:21 and 15:26 (5 min idle,
   "An existing connection was forcibly closed by the remote host" from a plain .NET socket, i.e.
   without MATLAB); 1, 2, 10 and 15 min idle passed (the 30 min step was not run). So the 33220A
   itself drops idle connections now and then; 1.2.1 therefore replaces a connection idle for more
   than 30 s before use instead of sending on it (owner decision 2026-10-12).
2. **ch3** has worked normally in every measurement (integrity and signal check OK); the fault of
   2026-10-08 has not recurred.
3. **Signal check levels** (1 s without excitation, after the 3 s settle wait) were 66–72 dB SPL at
   the first Connect (12:11, before step 5; the procedure connects the loudspeaker from step 5) and
   82–85 dB SPL at every later Connect; the pre-roll of the measurement of step 5 was about 45 dB SPL. Not
   investigated (low-frequency settling after the 0.7 Hz high-pass, room or electrical noise).
4. At 0.05 Vpp (direct drive, about 3.4 mVpk at the loudspeaker) most lines failed coherence or SNR
   (1403 / 1473 of 2191, no calibration loaded); at 0.5 and 1 Vpp none did.

## Hardware check of 1.2.1 (WO-003, branch `wo-003`), 2026-10-12: passed

SW-VERIFIED only (simulation, the protocol mock and a fake instrument on 127.0.0.1): the connection
check before every excitation and every 60 s while the window is idle, with the automatic re-opening
of a connection the generator dropped (`docs/workorder_after_hardware_check.md` section 1); the
EXCITATION controls (generator load, the amplitude at the loudspeaker in direct drive). The owner's
check, at the approved level 0.025 Vpk (0.05 Vpp), empty specimen section:

1. **Idle drop**: Connect and leave the window idle for at least 30 min, then a short measurement
   (1 repetition), then another one after 2 min idle. Expected: no error and no red stack trace in
   the MATLAB command window (idle connections are replaced before use, silently); the measurement
   runs; the output LED is on only during the sweep. A "Generator: connection re-opened (the
   instrument had closed it) …" line may appear only if a drop fell into the last 30 s before a
   use.
2. **Lost connection**: connected and idle, pull the generator's LAN cable for about 2 min. Expected:
   within a minute the Generator lamp turns red and the status reads "Connection lost - Disconnect
   and Connect"; nothing is switched on. Plug the cable back, Disconnect → Connect, one short
   measurement works.
3. **Generator load**: not connected, choose "power amplifier" (no excitation), Generator load 50 Ω,
   Connect: Setup > Connection shows "load 50"; Disconnect, back to "none (direct drive)": the list
   returns to High Z; Connect shows "load INF".
4. **Amplitude at the loudspeaker**: direct drive, the amplitude label set to "Speaker [Vpk]", 0.00345 Vpk (= 0.025
   Vpk programmed at 8 Ω). Expected: the excitation confirmation and the log line "Excitation
   confirmed" show generator 0.025 Vpk and loudspeaker about 0.00345 Vpk; the saved measurement has
   `metadata.drive` with both.

| Step | Status | Date, result |
|---|---|---|
| 1 idle drop, re-opened before the measurement | **HW-VERIFIED** | 2026-10-12, run from the worktree `tubebench-wo003` (window started 16:49 with commit 1b511ce; later commits were not loaded). Idle 17:00 → 18:07 (67 min): the window's minute check replaced the connection 76 times silently, no connection-lost entry; the measurement at 18:07:25 (preceded by a re-open) and the one at 18:11:29 (34 s after the last minute re-open, so re-opened again) ran without an error, integrity OK; no reset stack trace in the MATLAB command window (none all session) |
| 2 lost connection (cable pulled) | **HW-VERIFIED** | LAN cable pulled about 18:12: the minute check at 18:12:56 could not open a new connection (two attempts, 5 s each) and logged at 18:13:06 "Connection check: The connection to the generator was lost and could not be re-opened … then Disconnect and Connect."; the minute check stopped; nothing was switched on. Cable back, Disconnect → Connect (18:16:59), a measurement at 18:17:46 ran normally. The message contained MATLAB's own text of the failed connection (Korean, with a help link) - fixed afterwards: the error is English, the text goes to the transport log (`TestInstruments/scpiConnectFailureIsEnglish`). The owner saw the Generator lamp red and the status "Connection lost - Disconnect and Connect" until the reconnection |
| 3 generator load in the window | **HW-VERIFIED** | 16:49-16:51: "power amplifier", Generator load 50 Ω, Connect (the CHECK line of load 50 with an amplifier, the connection with load 50); Disconnect, back to direct drive → "Generator load: High Z for direct drive.", Connect sent `OUTP:LOAD INF`, Instruments table "limit 2 Vpp, load INF" |
| 4 amplitude at the loudspeaker | **HW-VERIFIED** | 16:52: Speaker [Vpk] 0.00345 → generator 0.025 Vpk (`VOLT 0.0500`); the confirmation line gave both; `metadata.drive` Vspk 0.00345 V, Voc 0.050025 Vpp. The stored `ui.amplitudeAt` was still the value of Connect (the label had been changed after it) - fixed in bee3508 (`MeasurementSession.setAmplitudeAt`, tested) |

Every step passed on the real instruments. With the rounded swap paths of the Calibration view
(software only; the owner confirmed them on screen captures, 2026-10-12) this is version 1.2.1,
merged into `main` on 2026-10-12.

## After the merge (1.2.0)

These items, the fixes the check asked for and the open owner decisions are collected in
`docs/workorder_after_hardware_check.md` (WO-003, 1.2.1).

* **Reprocess the five lab folders into NEW folders** (`data/20261009_192503_oneload_sweep`,
  `20261009_201658_oneload_sweep`, `20261010_234024_oneload_sweep`, `20261010_234354_oneload_sweep_empty75`,
  `20261010_235332_oneload_sweep_metasil-cell1`): since 2026-10-11 every swept-sine frequency line is
  centred on its frequency (`docs/theory.md` section 4, step 3), which changes every saved sweep
  result slightly - measured read-only in memory on these folders: median phase change of the raw
  relative responses 3.5–6.2·10⁻⁴ rad, on the valid lines |ΔR| ≤ 6·10⁻³ and |ΔZt| ≤ 2.4·10⁻³ ρc,
  0–2 lines per folder change validity. Reprocessing writes a new folder; the saved folders are
  never overwritten (`tim.app.saveMeasurement`). Which calibration to use (the existing files,
  whose C_k come from the old line band, or calibrations recomputed from their saved raw
  switching sweeps) is an open owner question. The sweep-gate change does not affect them (the
  lab sweeps keep the margin; bit-identical results).
  **Done 2026-10-12** with version 1.2.1 (commit 0025bdf). Owner decision 2026-10-12: all five
  with the existing calibration `CAL-20261010-212544` (the first two had used
  `CAL-20261009-191631`). Each was processed as File > Open measurement (the tube set-up of its
  `config.json`, the recorded microphone mapping) → Reprocess → Save. The new folders have the same
  `meas` as their source (`isequaln`) and a `REPROCESSED.txt` naming the source and the
  calibration; the source folders were only read.

  | Source folder | New folder | Valid lines (R) | Change on lines valid in both |
  |---|---|---|---|
  | `20261009_192503_oneload_sweep` | `20261012_200336_oneload_sweep` | 1860 → 1884 (1918 → 1929) | \|ΔR\| ≤ 0.043 (median 0.0057), \|ΔZt\| ≤ 0.034 ρc |
  | `20261009_201658_oneload_sweep` | `20261012_200351_oneload_sweep` | 1622 → 1634 (1721 → 1745) | \|ΔR\| ≤ 0.032 (median 0.0064), \|ΔZt\| ≤ 0.016 ρc |
  | `20261010_234024_oneload_sweep` | `20261012_200403_oneload_sweep` | 2096 → 2096 (2125 → 2125) | \|ΔR\| ≤ 0.0021, \|ΔZt\| ≤ 5·10⁻⁴ ρc |
  | `20261010_234354_oneload_sweep_empty75` | `20261012_200415_oneload_sweep_empty75` | 2045 → 2046 (2104 → 2105) | \|ΔR\| ≤ 0.0043, \|ΔZt\| ≤ 6·10⁻⁴ ρc |
  | `20261010_235332_oneload_sweep_metasil-cell1` | `20261012_200428_oneload_sweep_metasil-cell1` | 1591 → 1591 (1858 → 1859) | \|ΔR\| ≤ 0.0046 |

  The three folders of 2026-10-10 change only by the centred lines. The two of 2026-10-09 change
  mostly by the calibration: lines without a valid calibration 303 → 95, so more valid lines.
  These two were measured the day before that calibration was made. The folders with d = 53.3 mm
  (`…201658…`, `…metasil-cell1`) keep the calibration-context warning: the port distances
  [29 135.3 29] mm differ from the calibration set-up ([29 157 29] mm), so its empty-tube check
  (Test E) does not apply to them.
* **Rewrite `config/user_config.json` in the new layout** (`formatVersion` 2, D7, approved by the
  owner 2026-10-11): load it with `tim.app.loadConfig`, write it with `tim.app.saveConfig`, review
  the diff (only the layout may change: `generator.driver`, `daq.driver`, the driver sub-structs),
  and check that it loads without a warning and gives the same configuration as before.
  **Done 2026-10-12** (after the merge of 1.2.1): the rewritten file loads without a warning and
  gives the same configuration (`isequaln`), and `validateConfig` is silent. The diff has the new
  layout (`generator.driver` with `generator.keysight33220a`, `daq.driver` with `daq.lanxi`, no
  `lanxi` section) and the defaults the file did not name yet, now written out with unchanged
  values (`ui.amplitudeAt`, `generator.allowUnconfirmedOff`, `amplifier.inputImpedance_ohm`, the
  `loudspeaker` section). `TestConfiguration/configFilesLoad` now requires the current layout of
  every file in `config/`.

## Required hardware tests (in this order)

See `validation_procedure.md` for the exact steps and pass criteria. The script
`examples/hardware_commissioning.m` runs them section by section.

1. H0 network/identification (done)
2. H1 Test A: acquisition with microphones connected; INVALID flags gone; TEDS found; background level plausible
3. H2 channel identification (tap test)
4. H3 generator output at low level (sine 1 kHz, 0.05 Vpp) with the amplifier gain set low; overload margin
5. H4 sweep timing (trigger latency, pre/post margins)
6. H5 Test B single frequency (SNR, repeatability, clock offset)
7. H5b measure the geometry (calipers) and enter it **before** the calibration (the calibration
   stores the port distances and its automatic Test E uses them)
8. H6 Test C switching calibration with the EMPTY 75 mm section (ends with the automatic Test E,
   `cal.meta.emptyCheck`) and consistency
9. H7 Test D (rigid plug) and Test E repeated (plug removed, EMPTY section kept mounted)
10. H8 Test G stepped vs sweep
11. Enter the experimentally validated bands in `cfg.analysis.validatedBands`
