# Hardware verification status

Legend: **HW-VERIFIED** = exercised against the real instrument in this lab;
**SW-VERIFIED** = verified only with mocks / simulation / recorded fixtures;
**PENDING** = needs the physical test described in `validation_procedure.md`.

Hardware sessions so far, all from this PC via the instruments' link-local Ethernet addresses and
all with software 1.1.0 (before the instrument interface of WO-001):

* **2026-10-08**: identification, LAN-XI recorder cycle and bench tests without the tube; until
  21:01 the generator output was never switched on. From 21:01 the 33220A drove the loudspeaker
  directly, without an amplifier, at up to 0.5 Vpk (section "Bench test with excitation").
* **2026-10-09 and 2026-10-10**: in the tube - two switching calibrations, each with its automatic
  empty-tube check, and five swept-sine measurements at 0.1 Vpk (0.2 Vpp), direct drive (section
  "In-tube sessions 2026-10-09 / 2026-10-10").

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
| 33220A configure sine/sweep/noise, `*TRG`, `*OPC?`, `OUTP ON/OFF` | SW-VERIFIED | mock; SCPI strings verified against the manual (docs/ref_33220A_scpi.md). **PENDING** on hardware |
| 33220A amplitude read-back safety check | SW-VERIFIED | PENDING on hardware |
| SCPI transport: a late reply after a query time-out is discarded; the next query resynchronises with `*IDN?` (audit fix 2026-10-11) | SW-VERIFIED | local fake instrument on 127.0.0.1 (`TestInstruments/scpiLateReplyIsNotTakenAsTheNextAnswer`); not exercised on the 33220A (a time-out needs a slow or interrupted link) |
| LAN-XI: a fault while a recording starts (POST, its reply lost, or the RecorderRecording wait) closes the stream and stops the recording (audit fix 2026-10-11) | SW-VERIFIED | mock fault injection (`TestInstruments/lanxiStartFailureReleasesTheStream`); PENDING on hardware |
| LAN-XI REST client (GET/PUT/POST, HTTP 403 handling) | HW-VERIFIED | `PUT /create` in Idle → `403 "Cannot create recording in module state Idle"` |
| LAN-XI open → create → TEDS detect → setup → stream → stop → finish → close | HW-VERIFIED | full cycle, module returned to Idle |
| Recovery from an unexpected state (`shutdown`) | HW-VERIFIED | after a client-side timeout the module was in RecorderStreaming and was returned to Idle |
| `PUT /channels/input` duration | HW-VERIFIED | **> 10 s** on this module, so the timeout was raised to 60 s |
| Binary stream decoding (SignalData, Interpretation, DataQuality) | HW-VERIFIED | 2 s at 16384 S/s × 4 ch: 128 SignalData, 4 Interpretation, 4 DataQuality messages, 0 corrupt bytes, 0 timestamp gaps; ScaleFactor 11.885 = 10 V × 10^(1.5/20); unit "V"; bit-identical re-decode with random chunking. Fixture: `tests/fixtures/lanxi_stream_3676_noise_16k.*` |
| Data unit / single application of sensitivity | HW-VERIFIED | stream unit "V" with the default transducer |
| DataQuality flag reporting | HW-VERIFIED | flag 8 (INVALID: cable fault / CCLD / overload) reported on all 4 channels (see below) |
| TEDS reading | HW-VERIFIED (ch1, ch2, ch4) | bench 2026-10-08 18:02: Type 4957, 10.43 / 11.87 / 10.96 mV/Pa; **ch3: no TEDS** |
| Microphone signals (4957 via CCLD) | HW-VERIFIED (ch1, ch2, ch4); **ch3 FAULT** | background ≈ 54 dB SPL (100–5000 Hz) on ch1/2/4, no flags; ch3 INVALID flag, DC −0.18…−0.40 V |
| 33220A sweep/sine configuration + read-back, safety refusals | HW-VERIFIED (output OFF) | bench 2026-10-08: 80–5500 Hz LOG 5 s 0.05 Vpp read back; `outputOn` refused when not armed; 1 Vpp refused with maxVpp 0.2 |
| BNC/LEMO `ConnectorSelect` | observed: no difference | identical TEDS/signals with BNC and LEMO selected (microphones on the connectors in use) |
| Channel → port mapping | **PENDING** | `tim.val.channelIdentification` |
| Excitation + acquisition (sweep timing, trigger latency) | HW-VERIFIED (bench and in-tube sweeps); formal test **PENDING** | bench B3 2026-10-08: sweep start, duration −0.05 %, ≈ 0.26 s from the software trigger to the acoustic start; the 20 sweeps of the five in-tube measurements of 2026-10-09/10: excitation detected in every repetition, sweep-law duration error −0.01 … +0.11 %. The formal `tim.val.sweepTimingTest` (H4) has not been run |
| Single-frequency test (Test B) | **PENDING** | bench B2 2026-10-08 (1 kHz sine, 0.1 and 0.5 Vpk: SNR and block scatter, section below) covers the excitation path; the formal `tim.val.testB_singleFrequency` (H5) has not been run |
| Switching calibration on hardware (Test C) | **PENDING** (consistency) | two switching calibrations made in the tube with the empty 75 mm section (CAL-20261009-191631, CAL-20261010-212544; section "In-tube sessions"); the consistency criteria of Test C (`tim.val.testC_calibrationConsistency`) not evaluated |
| Rigid termination (Test D), empty tube (Test E), stepped vs sweep (Test G) | **PENDING** | the automatic empty-tube check of both calibrations passed (section "In-tube sessions"); Test D, the repeated Test E after it (H7) and Test G not run; the geometry is still the CAD design (calipers pending) |
| GUI | SW-VERIFIED | simulation only |
| Instrument interface of 1.2.0 (WO-001, branch `wo-001`: drivers through the registry, configuration by driver name, identity display in the window; review fixes of 2026-10-11) | SW-VERIFIED | simulation only (contract tests, bus-traffic fixtures, hidden-window tests). **PENDING** the owner's hardware check (WO-001 §0.3) - steps in the section "Pending: hardware check of the refactored drivers" below |

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
| 10-09 19:20 | `data/20261009_192503_sweep`, empty 75 mm section, 80–5500 Hz | integrity OK; 1860 of 2191 lines valid (R: 1918); termination not anechoic (τ, TL masked); evaluated in theory.md ("First lab data") |
| 10-09 20:15 | `data/20261009_201658_sweep`, 80–5500 Hz | integrity OK; d entered as 53.3 mm (M2–M3 135.3 mm instead of 157 mm), so the calibration's empty-tube check does not apply (warning in the result); what was mounted is not recorded in the folder |
| 10-10 21:26 | switching calibration `CAL-20261010-212544`, empty 75 mm section, sweep 80–5500 Hz | C_k valid on 96–97 % of the lines; automatic empty-tube check **passed**: \|τ\| error 0.007, τ phase error 0.80° rms, R consistency 0.012, 2031 lines |
| 10-10 21:34 | `data/20261010_234024_sweep` (saved 23:40), no specimen name, d = 75 mm, 80–5500 Hz | integrity OK; 2096 of 2191 lines valid (R: 2125) |
| 10-10 23:43 | `data/20261010_234354_sweep_cyl75`, specimen "cyl75", 80–7300 Hz | integrity OK; 2045 lines valid (R: 2104) |
| 10-10 23:52 | `data/20261010_235332_sweep_metasil-cell1`, specimen "metasil-cell1", d entered as 53.3 mm, 80–7300 Hz | integrity OK; 1591 lines valid (R: 1858); same port-distance warning as 10-09 20:15 |

These runs exercised the excitation, acquisition, calibration and processing chain on the real
instruments. They are not the formal Tests C, D, E (H7) or G: the consistency of the calibration
(repeated configuration I) was not evaluated, the termination is not anechoic, and the geometry
and the temperature have not been measured. Those rows stay **PENDING** above.

## Pending: hardware check of the refactored drivers (WO-001, branch `wo-001`)

Since 2026-10-11 the 33220A and the LAN-XI are driven through the instrument contract and the
driver registry (`docs/instrument_interface.md`, `docs/workorder_instrument_interface.md`). This is
**SW-VERIFIED only**: the full test suite in simulation (299 / 299 on 2026-10-11), the contract
tests of every driver, and the bus-traffic tests, which show that a simulated session sends the same
SCPI commands and REST requests as the code before WO-001 (three documented changes of order on
fault paths, approved by the owner on 2026-10-11: closing the window inside a sweep, a Stop during
the LAN-XI connect step, and D24 - on a Stop or an error of the acquisition the generator output
is switched off before the LAN-XI stop request, not after it).
Nothing of WO-001 has run on the real instruments yet. The owner's check (WO-001 §0.3), each step
only with the owner present; at the first surprise: output off at the generator, close the window,
report:

1. **Reconnect** the 33220A (LAN, 169.254.2.20:5025) and the LAN-XI 3676 (169.254.64.156) as on
   2026-10-08, no address or firmware change; the microphones on their channels; amplifier at
   minimum gain (or direct drive), loudspeaker connected only for steps 5-7. Check out `wo-001`;
   `config/user_config.json` stays as it is. Expected: both instruments answer as before; the
   33220A output LED off.
2. **The lab file loads unchanged**: `cfg = tim.app.loadConfig('config/user_config.json')` gives
   no warning; `cfg.generator.driver` `'keysight33220a'`, `cfg.daq.driver` `'lanxi'`,
   `cfg.daq.lanxi.connector` `'BNC'`, `cfg.generator.maxVpp` 2.
3. **Connect and identify with the output off** (script, nothing is switched on):
   `s = tim.app.MeasurementSession(cfg); s.connect(); disp(s.Gen.identity()); disp(s.Daq.identity()); s.Gen.isOutputOn(1)`,
   then `s.close()`. Expected: 33220A `MY44032054`, firmware 2.02; LAN-XI 3676-B-040, s/n 110283,
   firmware 2.10.0.610; `isOutputOn(1)` false and the output LED off; after `close()` the
   generator front panel is in local mode, and a new session (`s2 = tim.app.MeasurementSession(cfg);
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
   configured default 0.2 Vpp (EXCITATION amplitude ≤ 0.1 Vpk; e.g. 0.05 Vpp first), swept sine,
   one repetition, the amplifier record entered; answer the excitation confirmation only after the
   owner agreed. Expected: the output LED is on only during the sweep; the sweep lies inside the
   record on ch1, ch2, ch4; no integrity error apart from ch3; the output LED off afterwards.
6. **Stop during a measurement**: the same level, a longer sweep (e.g. 5 s, 4 repetitions); press
   Stop in the middle. Expected: the output LED goes off at once (since D24 the output is switched
   off before the LAN-XI module is stopped); the window says "Measurement stopped by the
   operator. Generator output off (confirmed)."; the partial data are kept; the next measurement
   works without reconnecting.
7. **Output-off read-back**: after steps 5 and 6 the status line shows no "Generator output not
   confirmed off"; the 33220A shows the output off (LED) - the read-back (`OUTP?`) and the
   instrument agree.
8. **Closing**: close the window while connected, once idle and once during a measurement.
   Expected: the closing window lists "Generator output off (confirmed)" and "Instruments
   disconnected"; the output LED stays off; the generator is back in local mode; at the next
   Connect the checklist step "LAN-XI recorder state Idle" reads "Idle" (not "was ... returned
   to Idle").

| Step | Status | Date, result |
|---|---|---|
| 1-2 reconnect, lab file loads | **PENDING** | |
| 3 connect and identify, output off | **PENDING** | |
| 4 window: instruments in use, identities | **PENDING** | |
| 5 short measurement at an approved level (≤ 0.2 Vpp) | **PENDING** | |
| 6 Stop during a measurement | **PENDING** | |
| 7 output-off read-back | **PENDING** | |
| 8 closing (idle, during a measurement) | **PENDING** | |

Only when every step has passed on the real instruments: HW-VERIFIED here, version 1.2.0
(`tim.app.softwareVersion`) and the merge of `wo-001` into `main`.

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
