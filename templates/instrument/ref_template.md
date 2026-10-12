# TODO vendor model — verified protocol reference used by `tim.instr.TODO<Name>`

<!-- TEMPLATE (docs/adding_an_instrument.md, step 7). Copy to docs/ref_<instrument>.md and
     fill in every TODO. Every command, reply format and limit the driver and its mock use
     appears here WITH ITS SOURCE (manual section / page). Never guess: an item the manual does
     not state is marked NOT VERIFIABLE and the driver must not rely on it. Delete this comment. -->

Source: *TODO manual title*, publication number TODO, edition TODO (date TODO), obtained from
TODO (vendor download / the owner's copy). Page numbers below are the TODO printed / PDF page
numbers. Items marked **NOT VERIFIABLE** are not stated in the manual and the driver does not rely
on them.

Real instrument (read-only identification, date TODO, only with the owner present):
`TODO the identification reply exactly as received`.

Interface: TODO (TCP socket / VISA resource / serial port / REST / vendor library), how it is
addressed (TODO address and port; set on the instrument, never changed by this program), message
termination TODO, MATLAB interface TODO (`tcpclient`, `visadev`, `serialport`,
`matlab.net.http`, `daq`, `audioPlayerRecorder`, `NET.addAssembly`, `loadlibrary`) and the MATLAB
product it needs (none / TODO).

## Commands and replies

| Purpose | Command / call | Manual section, page | Notes |
|---|---|---|---|
| Identify | TODO | TODO | reply format TODO; match the model, not the vendor text |
| Output off | TODO | TODO | state after power-on TODO; what "off" means (relay open / 0 V) |
| Output on | TODO | TODO | never a command that switches the output on by itself |
| Output state query | TODO | TODO | reply format TODO (read-back kind `instrument`) |
| Error query | TODO | TODO | queue length TODO; reply format TODO; "no error" code TODO |
| Clear errors | TODO | TODO | |
| Function sine | TODO | TODO | |
| Frequency | TODO | TODO | range TODO Hz |
| Amplitude | TODO | TODO | unit TODO (Vpp); range TODO per load setting |
| Offset 0 V | TODO | TODO | |
| Load setting | TODO | TODO | what it changes (programmed value only, or the output) |
| Sweep start / stop / time / spacing | TODO | TODO | sweep time range TODO s; LOG law stated? TODO |
| Sweep state | TODO | TODO | order of the settings the manual recommends |
| Trigger source / bus trigger | TODO | TODO | one sweep per trigger? output between sweeps at fStart? |
| Completion query | TODO | TODO | does it wait for the END of the sweep? (else: time-based `waitComplete`) |
| Noise | TODO | TODO | crest factor / rms definition TODO |
| Front panel back to local | TODO | TODO | |

For an acquisition device add: channel setup (rates the device runs **exactly**, coercion
rules), input ranges, coupling / high-pass, IEPE supply, TEDS, start / read / stop, the data
format and unit, the flags it reports (overload, open input, gaps) and how a stop is guaranteed
on every exit path.

For an interface of **function calls** instead of commands (a MATLAB toolbox such as the Data
Acquisition Toolbox or the Audio Toolbox, a vendor SDK), list the calls of the device session
(`docs/adding_an_instrument.md` section 4.1) instead, with the documentation that states them:

| Purpose | Function / property, arguments | Documentation (product, release, page or section) | Notes |
|---|---|---|---|
| Find and identify the device | TODO | TODO | model, serial and firmware fields TODO |
| Inputs: rate, range, coupling, IEPE current | TODO | TODO | is the rate coerced? read it back TODO |
| Output channel | TODO | TODO | what the output does after a stop and after release (keeps the last value?) TODO |
| Start, play and record a block, stop | TODO | TODO | queue length and the lag it gives TODO |
| 0 V on demand after a stop | TODO | TODO | |
| Errors and flags (underrun, overload, open input) | TODO | TODO | |
| Release | TODO | TODO | |

## Limits used in `capabilities()`

| Field | Value | Manual section, page |
|---|---|---|
| TODO e.g. `source.frequencyRange` | TODO | TODO |
| TODO e.g. `source.maxVpp`, `minVpp` per load | TODO | TODO |
| TODO e.g. `source.sweepTime` | TODO | TODO |
| TODO e.g. `source.outputImpedance_ohm` | TODO | TODO |
| TODO e.g. `acquisition.sampleRates` | TODO | TODO |

## Consequences for the driver

* TODO what the driver does because of the manual (e.g. the output is switched on only right
  before the trigger, because the output plays fStart between sweeps).
* TODO every **NOT VERIFIABLE** item and how the driver avoids relying on it.

## Suitability (WO-001 section 3; docs/adding_an_instrument.md step 2)

| Requirement | Met? | Evidence (manual section, page) |
|---|---|---|
| TODO each Must / Should item of the role(s) | TODO | TODO |
