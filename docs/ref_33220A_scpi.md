# Keysight/Agilent 33220A — verified SCPI reference used by `tim.instr.Keysight33220A`

Source: *Agilent 33220A User's Guide*, publication 33220-90002, Edition 4 (May 2007),
official Keysight download 9018-04437. Page numbers below are the printed manual page numbers.
Items marked **NOT VERIFIABLE** are not stated in the manual and the driver does not rely on them.

Real instrument (queried read-only on 2026-10-08):
`Agilent Technologies,33220A,MY44032054,2.02-2.02-22-2` (fields: firmware-boot-ASIC-PCB revision).

| Purpose | Command | Page | Notes |
|---|---|---|---|
| Identify | `*IDN?` | 250 | Do not hard-match vendor string (Agilent/Keysight). |
| Reset | `*RST` | 251 | Aborts sweep/burst in progress. Does not clear error queue. |
| Clear status | `*CLS` | 273 | Clears error queue. |
| Operation complete | `*OPC?` | 253 | In BUS-triggered sweep returns 1 when the sweep completes (p.220, 232). |
| Error queue | `SYST:ERR?` | 249, 284 | FIFO, 20 entries. Format `-113,"Undefined header"`. Empty-queue string ("No error", code 0) — parse the integer, do not match the text. |
| Function | `FUNC SIN` | 179 | Also `NOIS` (noise cannot be swept, p.99). |
| Frequency | `FREQ <Hz>` | 181 | Sine 1 µHz – 20 MHz. |
| Amplitude | `VOLT <value>` | 182 | Unit from `VOLT:UNIT` (default VPP). 10 mVpp–10 Vpp into 50 Ω; 20 mVpp–20 Vpp into open circuit. |
| Amplitude with the output on (1.6.0, `setAmplitude`) | `VOLT <value>` sent while `OUTP ON` | 182 | The same command as above; `OUTP` is not sent. What the output does while the level changes (an attenuator relay switching, a glitch) and the `VOLT?` read-back with the output on are **NOT VERIFIABLE** from this reference: hardware check WO-006 section 6 item 1 (`docs/workorder_equalizer.md`); the settling time of every step covers a short glitch. The driver writes six significant digits here (`%.6g`; the configure commands keep `%.4f`), so the read-back resolution of the instrument is to be checked at the same time. |
| Amplitude unit | `VOLT:UNIT VPP` | 191 | dBm not allowed with high-Z load. |
| Offset | `VOLT:OFFS <V>` | 184 | \|Voff\| + Vpp/2 < Vmax. Amplitude/offset can silently modify each other (-221). |
| Load setting | `OUTP:LOAD INF` / `50` | 189 | Only rescales displayed/programmed values; true source impedance is always 50 Ω. Stored in non-volatile memory. Query returns `9.9E+37` for INF. |
| Output | `OUTP ON` / `OUTP OFF` | 188 | Default OFF. ~1 ms relay glitch; set minimum amplitude first. |
| APPLy | `APPL:SIN f,A,off` | 176 | **Forces OUTP ON, TRIG:SOUR IMM and disables sweep.** The driver never uses APPLy. |
| Sweep start/stop | `FREQ:STAR`, `FREQ:STOP` | 217 | |
| Sweep spacing | `SWE:SPAC LIN` / `LOG` | 219 | Log sweep: "constant octaves (decades) per second" (p.342); explicit formula NOT given. Sweep is made of discrete phase-continuous steps whose number is chosen automatically from the sweep time (p.100, 219, 342). |
| Sweep time | `SWE:TIME <s>` | 219 | 1 ms – 500 s. |
| Sweep enable | `SWE:STAT ON` | 219 | Enable **last** (p.99, 219). Disables burst/modulation. |
| Trigger source | `TRIG:SOUR BUS` | 220, 231 | BUS: one sweep per `*TRG`. IMM: continuous. |
| Bus trigger | `*TRG` | 232 | Ignored unless TRIG:SOUR BUS (`-211 Trigger ignored`). |
| Trigger out | `OUTP:TRIG ON`, `OUTP:TRIG:SLOP POS` | 221, 233 | With BUS source: pulse >1 µs at the start of each sweep on rear Trig Out. |
| Sync during sweep | front-panel Sync | 68–69, 100 | Marker OFF: high at sweep start, low at midpoint. |
| Idle in triggered sweep | — | 100, 104 | Before trigger and after the sweep the output sits at the **start** frequency. |
| Remote/local | `SYST:LOC`, `SYST:REM` | 254 | Supported over LAN socket. |
| Display text | `DISP:TEXT '...'`, `DISP:TEXT:CLE` | 251 | |

Remote interface: raw socket on TCP 5025 (p.257), commands terminated by LF (p.279).

Consequences for the measurement design:

* With BUS-triggered sweep, the loudspeaker is driven with a continuous sine at `f_start`
  whenever the output is ON and no sweep is running. The driver therefore enables
  `OUTP ON` only immediately before `*TRG` and switches it OFF as soon as the sweep has
  ended, and the analysis does not assume silence before the sweep.
* The manual gives no explicit log-sweep law and states that the sweep is stepped; the
  analysis therefore never uses an ideal inverse filter of the generator signal. It uses
  only microphone-to-microphone ratios, which are independent of the excitation waveform
  (see `docs/theory.md`).
* Whether `*TRG` executes with `OUTP OFF` is NOT VERIFIABLE; the driver turns the output
  ON before triggering.
