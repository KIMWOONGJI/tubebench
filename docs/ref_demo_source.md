# Demo signal generator DEMO-SG1 — protocol reference used by `tim.instr.DemoSource` (simulation only)

**The DEMO-SG1 does not exist.** It is the instrument of the worked example of
`docs/adding_an_instrument.md` (section 13): the driver `tim.instr.DemoSource` (registry name
`demo`) and its protocol mock `tim.instr.MockDemoSource` were made from
`templates/instrument/TemplateSource.m` and `MockTemplateSource.m` by following that guide. For a
real instrument this document would quote the vendor's programming manual; here it **defines**
the instrument and so plays the part of its manual: the section numbers ("ref 3.2") in the
driver, the mock and the tables below refer to this document. The registry refuses the driver in
hardware mode (`describe().simulation = 'only'`, `tim:instr:simulationOnly`).

Source: this document (WO-001 Part 2, 2026-10-11). In a real reference: the manual's title,
publication number, edition, date and where it was obtained, and its page numbers.

Real instrument: none. The mock answers `*IDN?` with `tubebench demo,DEMO-SG1,DEMO-0001,1.0`
(fields vendor, model, serial number, firmware). A real reference quotes the reply read from the
instrument, read-only and with the owner present (guide step 10a).

## 1. Interface

SCPI over a TCP socket, port 5025, commands and replies terminated by LF; one command or query
per line, `;` separates commands in one line. A real driver would use `tim.instr.ScpiTcpTransport`
(`tcpclient`, base MATLAB). Headers are not abbreviated and carry the channel number: `SOUR1:`,
`OUTP1:`, `TRIG1:` (the DEMO-SG1 has one channel).

## 2. Common commands

| § | Purpose | Command | Reply / effect |
|---|---|---|---|
| 2.1 | Identify | `*IDN?` | `<vendor>,<model>,<serial>,<firmware>`; model `DEMO-SG1` |
| 2.2 | Error queue | `SYST:ERR?` | `<code>,"<text>"`, oldest first; `0,"No error"` when empty; 16 entries, the last one replaced by `-350,"Queue overflow"` when full |
| 2.2 | Clear errors | `*CLS` | empties the error queue |
| 2.2 | Error codes | - | `-113` undefined header; `-222` data out of range (the value is set to the nearest limit); `-224` illegal parameter value; `-211` trigger ignored |
| 2.3 | Front panel back to local | `SYST:LOC` | no effect on the output |
| 2.4 | Power-on state | - | output off; sine 1 kHz, 0.1 Vpp, offset 0; sweep off; trigger source IMM |

## 3. Generator commands

| § | Purpose | Command | Range / reply | Notes |
|---|---|---|---|---|
| 3.1 | Output on / off | `OUTP1:STAT ON` / `OUTP1:STAT OFF` | | relay output: off = disconnected; source impedance 50 Ω |
| 3.1 | Output state | `OUTP1:STAT?` | `ON` or `OFF` | the instrument's state, also after a change at the front panel |
| 3.2 | Function | `SOUR1:FUNC SIN` | `SIN` only; anything else `-224` | **no noise function** |
| 3.2 | Frequency | `SOUR1:FREQ <Hz>`, `SOUR1:FREQ?` | 0.1 Hz – 100 kHz | a new frequency is phase continuous; reply `%+.13E` |
| 3.2 | Amplitude | `SOUR1:VOLT <Vpp>`, `SOUR1:VOLT?` | 2 mVpp – 10 Vpp | always Vpp, the **open-circuit** voltage (no load setting, no unit command) |
| 3.2 | Offset | `SOUR1:VOLT:OFFS <V>` | ±5 V | |
| 3.3 | Sweep start / stop | `SOUR1:SWE:STAR <Hz>`, `SOUR1:SWE:STOP <Hz>` (+ `?`) | 0.1 Hz – 100 kHz | |
| 3.3 | Sweep time | `SOUR1:SWE:TIME <s>` (+ `?`) | 10 ms – 300 s | |
| 3.3 | Sweep spacing | `SOUR1:SWE:SPAC LOG` / `LIN` (+ `?`) | `LOG` or `LIN` | `LOG`: f(t) = f1·(f2/f1)^(t/T), no hold or return time |
| 3.3 | Sweep state | `SOUR1:SWE:STAT ON` / `OFF` | | set the sweep settings first and the state last; with the sweep on and trigger source BUS the output plays the start frequency until `*TRG` and again after the sweep |
| 3.4 | Trigger source | `TRIG1:SOUR BUS` / `IMM` | | BUS: one sweep per `*TRG` |
| 3.4 | Trigger | `*TRG` | `-211` unless trigger source BUS and the sweep on | starts the sweep |
| 3.4 | Completion | `*OPC?` | `1` | answers only when a triggered sweep has ended |

## 4. Limits used in `capabilities()`

| Field | Value | § |
|---|---|---|
| `source.waveforms` | `sine`, `sweep` (no noise) | 3.2, 3.3 |
| `source.sweepSpacing` | `LOG`, `LIN` | 3.3 |
| `source.frequencyRange` | [0.1 100000] Hz | 3.2 |
| `source.loads` | `INF` (the programmed level is the open-circuit voltage) | 3.2 |
| `source.maxVpp`, `minVpp` | 10 Vpp, 0.002 Vpp | 3.2 |
| `source.sweepTime` | [0.01 300] s | 3.3 |
| `source.outputImpedance_ohm` | 50 | 3.1 |
| `source.trigger`, `readback` | `bus` (`*TRG`), `instrument` (`OUTP1:STAT?`) | 3.1, 3.4 |
| `source.noiseCrest` | 3.3 (no noise output; the value the contract requires) | - |

## 5. Consequences for the driver

* The output is switched off right after the identification and before any setting; no level
  is programmed at connect.
* The level is checked against `generator.maxVpp` and 2 mVpp – 10 Vpp before any `SOUR1:VOLT`;
  `outputOn` reads `SOUR1:VOLT?` back and checks it again.
* The sweep settings are sent in the order of 3.3, the state last; every setting is read back.
* The output state is the reply `ON` / `OFF`; any other reply raises `tim:gen:verify`.
* `configureNoise` is refused (`tim:gen:unsupported`) without sending anything.
* The mock answers `*OPC?` at once (it has no clock of its own); the session asks only after the
  samples of the sweep have been recorded, so the simulated sweep has ended.

## 6. Suitability (WO-001 section 3; guide step 2)

| Requirement (generator) | Met? | Evidence |
|---|---|---|
| Must: output off by command, state read back from the instrument | yes | 3.1 (`OUTP1:STAT OFF`, `OUTP1:STAT?`) |
| Must: amplitude limit enforced by the driver before every level command | yes (driver) | `checkLevel`; 3.2 |
| Must: single logarithmic swept sine, 80 Hz – 5.5 kHz | yes | 3.3 (LOG, 0.1 Hz – 100 kHz) |
| Optional: stepped sine, noise | stepped sine yes (3.2); noise **no** (3.2) | the excitation mode `noise` is refused by `checkConfig` |
| Should: bus trigger, completion query waiting for the end of the sweep | yes | 3.4 |
