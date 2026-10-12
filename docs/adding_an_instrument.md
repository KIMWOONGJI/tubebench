# Adding an instrument (driver guide)

| | |
|---|---|
| For | a person who wants to use a generator or a DAQ that tubebench has no driver for - with or without Claude Code |
| Work order | WO-001 Part 2 (`docs/workorder_instrument_interface.md` section 5 and section 0, change A) |
| Contract | `docs/instrument_interface.md` - what a driver must do; this guide says how to get there |
| Templates | `templates/instrument/` - starting files that already pass the contract tests on their mocks |
| Worked example | the demo source `demo` (section 13): made from the templates by following this guide |
| Claude Code | `.claude/skills/add-instrument/SKILL.md` runs this guide step by step; it adds nothing to it |

tubebench talks to its instruments only through **drivers**: one MATLAB class per instrument that
implements the contract of `docs/instrument_interface.md`. The configuration chooses a driver per
role (`generator.driver`, `daq.driver`); the measurement session, the window, the calibration and
the analysis never change for a new instrument. Adding an instrument therefore means: check that
it can do what the measurement needs, write its driver, a software model of it (the protocol
mock) and their tests, test everything in simulation, and only then, step by step and with the
owner, on the real instrument.

Read this guide once completely before you start. Work in this order; every step ends with
something you can show.

| Step | What | Result |
|---|---|---|
| 1 | collect the facts | the filled-in fact sheet (section 1) |
| 2 | judge suitability | the suitability table; stop here if a Must item fails |
| 3 | copy the templates | the driver, mock and test files under their new names |
| 4 | write the driver | every `TODO` of the driver replaced by a fact from the manual |
| 5 | write the protocol mock | the instrument in software, coupled to the virtual tube |
| 6 | settings and configuration | defaults in the driver; a configuration file that selects it |
| 7 | protocol reference | `docs/ref_<instrument>.md` with a source for every command |
| 8 | register the driver | one line in `+tim/+instr/drivers.m` |
| 9 | test offline | driver tests, contract tests, full suite green; the window in simulation |
| 10 | verify on the hardware | four steps (a)-(d), each only with the owner present and agreeing |
| 11 | document and commit | `docs/hardware_status.md`, user guide, README; one commit per step |

Section 12 lists the safety rules, which apply throughout. Section 14 is a one-page checklist.

## 0. Before you start

You need:

* MATLAB R2022b with the Signal Processing Toolbox, this repository, and the MATLAB product the
  instrument's interface needs (section 1).
* **The instrument's programming manual** (PDF; from the vendor, or the owner's copy). Every
  command, reply format and limit the driver uses comes from it. Without the manual, stop: never
  guess a command, never copy one from another instrument "because it is SCPI too".
* For step 10 only: the instrument connected by the owner, and the owner present.

Read first: `docs/instrument_interface.md` sections 1-5 (roles, members, capabilities), 8 (timing)
and 11 (safety duties). Look at the driver of the lab instrument that is closest to yours:
`+tim/+instr/Keysight33220A.m` (SCPI generator), `+tim/+instr/LanXi.m` (network DAQ) or
`+tim/+sim/SimulatedCombined.m` (one device in both roles).

Run MATLAB from the project folder. Commands below are for the MATLAB command window unless they
say PowerShell. `run_tests` adds the project to the path itself; otherwise `addpath(pwd)` first.

## 1. Collect the facts

Fill in this fact sheet (it becomes the head of `docs/ref_<instrument>.md`, step 7). "Manual"
means: the manual section and page that state it.

| Fact | Where it comes from |
|---|---|
| Vendor, model, firmware version | the instrument's identification (ask the owner to read it from the front panel or the label); the manual's title page |
| Role(s): generator, acquisition, or both in one device | the manual (an analog output and inputs on one clock = both) |
| Interface and how it is addressed (IP address and port, VISA resource, COM port, NI device name, audio device name) | the instrument's own settings, as the owner has set them - **never change them** |
| The MATLAB interface and the product it needs (table below) | MathWorks documentation |
| Vendor software it needs (VISA library, NI-DAQmx, ASIO driver, an SDK) | the vendor's documentation; installing it needs the owner's approval |
| The programming manual: title, publication number, edition, date | the PDF |
| Output: what "off" means (a relay opens, 0 V, or the last value is kept), its state at power-on, its source impedance, its largest and smallest level | manual |
| Inputs: number, simultaneous sampling, sample rates, ranges, coupling / high-pass, IEPE supply, TEDS, data format and unit, the flags it reports | manual |

What the lab PC has (2026-10-11): MATLAB R2022b with the Signal Processing Toolbox, Data
Acquisition Toolbox 4.6 and Instrument Control Toolbox 4.7. The Audio Toolbox and the
Data Acquisition Toolbox support package for NI-DAQmx are **not** installed.

| Interface | MATLAB function | MATLAB product beyond the base | Notes |
|---|---|---|---|
| TCP socket, SCPI (LAN) | `tcpclient` | none | ready-made transport: `tim.instr.ScpiTcpTransport` (write, query, isOpen, setTimeout, close); the port is in the manual (often 5025) |
| VISA: USB-TMC, GPIB, LAN (VXI-11, HiSLIP) | `visadev` | Instrument Control Toolbox, plus a VISA library from the vendor | a transport with the methods of `ScpiTcpTransport` around `visadev` (`writeline`, `readline`, `configureTerminator`, `Timeout`) |
| Serial port (RS-232, USB virtual COM port) | `serialport` | none | the same transport shape around `serialport` |
| REST / HTTP | `matlab.net.http`, `webread`, `webwrite` | none | as `tim.instr.LanXiHttp` |
| Binary data stream over TCP | `tcpclient` | none | as `tim.instr.LanXiTcpStream` |
| NI-DAQmx device | `daq("ni")` | Data Acquisition Toolbox, its support package for NI-DAQmx and the NI-DAQmx driver | `checkInstalled()` checks the support package (contract section 2.1) |
| Audio interface | `audioPlayerRecorder`, `audioDeviceReader`, `audioDeviceWriter` | Audio Toolbox; on Windows `audioPlayerRecorder` needs an ASIO driver | samples in full-scale units, not volts (step 2) |
| Vendor SDK as a .NET assembly | `NET.addAssembly` | none (Windows) | |
| Vendor SDK as a C library (DLL) | `loadlibrary`, `calllib` | none; MATLAB needs the header file and a supported C compiler (see the `loadlibrary` documentation) | |

Check every function you plan to use in the MathWorks documentation of R2022b; the table says
where to look, not how to call it.

## 2. Judge suitability

Compare the instrument with the requirements of the measurement method (copied from WO-001
section 3; reworded after the design review, `docs/instrument_interface.md` section 13.2). "Must"
items are hard limits. For each item of the instrument's role(s) write down: met / not met /
not stated, and the manual page that proves it.

| Role | Requirement | Why |
|---|---|---|
| Acquisition | **Must:** ≥ 4 analog inputs sampled **simultaneously on one clock** | transfer functions between channels; skew is a phase error |
| Acquisition | **Must:** IEPE/CCLD supply per channel with a constant current that the microphone data sheet allows (the lab's LAN-XI supplies 4 mA; compare the device's IEPE current with the B&K 4957 data sheet), or an external supply | B&K 4957 microphones |
| Acquisition | **Must:** sample rate ≥ 2.2 × analysis fMax (4.5 kHz → ≥ 10 kS/s; now 16 384 S/s) with anti-alias filter, run at exactly the configured rate | spectral analysis to 4.5 kHz; a coerced rate mislabels the frequency axis |
| Acquisition | **Must:** continuous gap-free recording of ≥ 10 s with gap/overload detection, delivering data **while it records** (streaming, or background acquisition with a polling read); a device that delivers only whole blocks works only when it is also the generator (shared clock) | swept sine with pre/post-roll; integrity check; the session switches a separate generator on and off as samples arrive |
| Acquisition | Should: AC coupling/high-pass ≤ 1 Hz, input range ≤ 10 V peak, ≥ 24 bit, TEDS reading, data in volts (an input in full-scale units with an unknown gain gives levels in dB re FS only, unless its volts per full scale are measured) | dynamic range; sensitivities from TEDS; levels in Pa |
| Generator | **Must:** output can be switched off by command (no waveform, 0 V or disconnected - an analog output that keeps its last value must be set to 0 V), and its state read back from the instrument or, for the output of a shared-clock device that is also the DAQ, from the device session (task stopped, 0 V written). A generator that cannot report its state is accepted only when the owner allows it explicitly in the configuration (`generator.allowUnconfirmedOff`); the window then says so after every stop | safety rules (output off on connect, error, close) |
| Generator | **Must:** an amplitude limit that the driver enforces before every level command; an output programmed in full-scale units (audio interface) needs its measured volts per full scale at a fixed knob position (`generator.<driver>.vppAtFullScale`; `daq.<driver>.vppAtFullScale` for a combined driver) | loudspeaker/power limit |
| Generator | **Must:** a single logarithmic swept sine (the switching calibration and Test E always sweep); stepped sine and noise optional; frequency 80 Hz–5.5 kHz | excitation signals; the calibration method does not change |
| Generator | Should: software (bus) trigger, completion query that waits for the end of the sweep (*OPC? or equivalent, or time-based) | timing of the sweep in the record |
| Both | No hardware synchronisation between generator and DAQ is needed | the estimator uses channel ratios only (theory.md §4) |
| Both | One device may take both roles (e.g. a DAQ card with analog output) | factory must allow one object for both roles |

**If a Must item is not met, stop.** Write down which item, the manual page, and what would work
instead, and report it to the owner before writing any code. Examples: a DAQ with two inputs - two
such devices cannot be combined (one object per driver), so a 4-input device is needed; inputs
without IEPE supply - an external IEPE supply and `acquisition.ccld = false`; a generator without
a logarithmic sweep - not usable (the calibration method does not change).

What the answers decide (the contract sections in brackets):

* **Which template** (step 3): a generator with its own clock that answers commands
  (`TemplateSource`); a DAQ whose data arrive while it records (`TemplateAcquisition`); one device
  with an output and the inputs on one clock (`TemplateCombined`). A DAQ that delivers only whole
  blocks after recording can only be used as such a combined device (`needsOwnSource`, 8.2).
* **Output off** (3.1): a relay output is off at once; a sample-producing output (DAQ analog
  output, audio) must write 0 V after every stop and fade every plan to 0 V.
* **Read-back** (3.2): `'instrument'` (an output-state query), `'device'` (the device session of a
  shared-clock device), `'none'` (cannot report - only with `generator.allowUnconfirmedOff`, an
  owner decision).
* **Levels in full-scale units** (3.4): `levelKnown = false`; the driver needs the setting
  `vppAtFullScale` (measured with a voltmeter at a fixed knob position, no default), refuses any
  level above full scale or `generator.maxVpp`, and `checkConfig` requires the setting in hardware
  mode.
* **Inputs in full-scale units** (4.2): `dataUnit = 'FS'` unless `daq.<driver>.voltsAtFullScale`
  (1 x C, measured) is configured.
* **Sample rate** (4): the device must run at exactly the configured rate; list the rates it runs
  exactly (`sampleRates`) or give a range (`sampleRateRange`); `prepare` refuses any other rate
  with `tim:<driver>:rate`.
* **Completion of the sweep** (3.2): if the manual does not say that the completion query waits
  for the end of the sweep, `waitComplete` is time-based.

Write the result into the suitability table at the end of `docs/ref_<instrument>.md` (step 7).

## 3. Copy the templates

Choose the names:

| Name | Rule | Example (section 13) |
|---|---|---|
| class name `<Name>` | a MATLAB class name in UpperCamelCase, after the model | `DemoSource` |
| registry name | lower case letters and digits, starting with a letter; unique in `tim.instr.drivers()`; it is the configuration value of `generator.driver` / `daq.driver`, the name of the settings sub-struct, the key of the connect step and the middle part of the driver's error identifiers `tim:<registry name>:<what>` | `demo` |

Copy the three files of the template and rename the template's names in them. In MATLAB, with
the project folder as the current folder (check with `pwd`; the files are UTF-8 and stay so):

```matlab
addpath(pwd);                     % the project folder
from = 'TemplateSource';          % TemplateSource | TemplateAcquisition | TemplateCombined
name = 'DemoSource';              % <Name>
reg  = 'demo';                    % <registry name>
src = fullfile(pwd, 'templates', 'instrument');
pairs = {[from '.m'],          fullfile('+tim', '+instr', [name '.m']); ...
         ['Mock' from '.m'],   fullfile('+tim', '+instr', ['Mock' name '.m']); ...
         ['Test' from '.m'],   fullfile('tests', ['Test' name '.m'])};
for i = 1:size(pairs, 1)
    dst = fullfile(pwd, pairs{i, 2});
    assert(~isfile(dst), '%s exists already', dst);
    txt = tim.app.readTextUtf8(fullfile(src, pairs{i, 1}));
    txt = strrep(txt, from, name);                 % class names (also Mock..., Test...)
    txt = strrep(txt, upper(from), upper(name));   % the same in the help lines
    txt = strrep(txt, lower(from), reg);           % registry name, settings, error identifiers
    fid = fopen(dst, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(txt, 'UTF-8')); fclose(fid);
end
```

Then list every place that needs an instrument fact (PowerShell, in the project folder):

```powershell
Select-String -Path '+tim\+instr\DemoSource.m', '+tim\+instr\MockDemoSource.m', 'tests\TestDemoSource.m' -Pattern 'TODO'
```

Each `TODO` line holds a placeholder value of an imaginary instrument (a generic SCPI generator,
a 4-input IEPE DAQ, a DAQ card with an output). The templates work as they are - so a forgotten
placeholder would not be noticed in simulation. Replace **every** `TODO` with what your manual
says, and delete the word `TODO` when the line is right. The help text at the top of each file
starts with a paragraph about the template ("THIS IS A TEMPLATE ...") that contains the word
too: replace that paragraph by a description of your driver, mock or test. When you are done the
command above finds nothing. The trailing comments of renamed lines may need re-aligning.

Do not edit `templates/instrument/` itself; `tests/TestInstrumentTemplates` checks that the
templates still pass the contract tests.

## 4. Write the driver

Work through the copied driver from top to bottom. For each part, what it must do (contract
section in brackets) and where the facts come from:

**Help header.** Replace the template paragraph and the `TODO` line of the help text by what the
driver is: the instrument, its interface, the manual and `docs/ref_<instrument>.md`. Keep the
safety model text: it is the contract the code follows.

**A function the instrument does not have** (e.g. noise, a load setting). Remove it from
`capabilities()` (`waveforms`, `loads`, ...) and delete its commands: a `configure*` method of a
waveform the instrument cannot play keeps only `assertOpen` and the refusal
`error('tim:gen:unsupported', ...)`, so it sends nothing (`checkConfig` then also refuses that
excitation mode). Keep the method itself - the contract requires it - and keep `noiseCrest` in the
capabilities (3.3, the contract test requires a value).

**Constructor / `fromConfig`** (2.1, 3.1, 11.1). Identify first (a read-only query), refuse
another model (`tim:<reg>:identity`; match the model text, not the vendor text, which changes with
company names), then **output off before any other setting**, then the settings that make the
instrument predictable (clear errors, load, amplitude unit). Never program a level at connect.
`fromConfig` builds the transport for hardware (`ctx.mode = 'hardware'`) or the protocol mock on
`ctx.rig` (simulation), reports its checklist step (`run` before opening anything, `ok` with the
identification), and closes the transport if the constructor fails. Product functions (`visadev`,
`daq`, ...) may be called only here and in instance methods, never at class level, so that the
class loads and the tests run on a PC without the product.

**Generator methods** (3.2-3.4). Every `configure*` switches the output off first, checks the
level **before any level command** (`checkLevel`: positive, at most `generator.maxVpp`, within
the instrument's range for the configured load), sends the settings in the order the manual
recommends, reads the instrument's error queue, reads the settings back and compares them
(`tim:gen:verify`, output off). `outputOn` only when armed (`tim:gen:notArmed`) and configured
(`tim:gen:mode`), after reading the programmed level back and checking it once more. Never use a
command that switches the output on by itself (the 33220A's `APPLy` does). `outputOff` and
`close` never throw (a failure is a warning), may be called any number of times and from inside a
callback. `isOutputOn` asks the instrument; an answer that is neither on nor off raises
`tim:gen:verify` - never report "off" without knowing it. `waitComplete` is never `true` before
the sweep has ended (time-based if the completion query does not wait for it). After `close()`
nothing is sent any more (`tim:instr:closed`).

**Acquisition methods** (4, 8, 11.1). The template talks to the device through a **device
session** object (`obj.Dev`, its methods are listed in the template header). For hardware, write
that class yourself as `+tim/+instr/<Name>Session.m`: a thin wrapper around the vendor interface
with exactly those methods, so that the driver reads the same on the hardware and on the mock.
`prepare` must run at **exactly** the configured rate (compare what the device reports and raise
`tim:<reg>:rate`), apply range, coupling and IEPE, and leave the device ready. `acquire` keeps the
template's structure: start, read in a loop, `onBlock(n)` after every block and at least every
0.25 s, a stall time-out, `onCleanup` that calls `AbortFcn` first and then stops the device on
every abnormal exit (the session sets `AbortFcn` to switch the source output off, so the
loudspeaker stops before your stop sequence), `close()` from inside `onBlock` ending with
`tim:instr:closed`. Data are volts at the input (no sensitivity), or full-scale units with
`dataUnit 'FS'`. Device flags go into `integrity.channelFaults` **in the driver's words**
(`noteFaults`). TEDS: `Teds = {}` when the device reads none (the sensitivities then come from
the certificate or nominal values).

**Combined device** (3.5, 8.3). Leave the planning engine of `TemplateCombined` as it is
(`acquire`, `render`, `apply`, `synthesize`, `haltOutput`, `finishOutput`, `endOutput`,
`endAcquire`; it is the engine of `tim.sim.SimulatedCombined`, and the contract tests run it on
the template's mock - which cannot show what the real device does, so step 10 checks the output
at its terminal). Replace only the device session calls; write the device session by section 4.1.
Two rules of the engine that the device session must support: every end of playing (normal, Stop,
error, close) plays the rest of the 5 ms fade, stops the device and **then** writes 0 V
(`endOutput`), each step even when the one before failed - so `Dev.writeZero()` must work after
`Dev.stop()`; and the block size is the setting `blockSamples` (any size the device needs; the
contract tests use it). The one exception to "leave the engine as it is" is a device whose output
is queued ahead (section 4.1). For an output in full-scale units (`levelKnown = false`): add the setting
`vppAtFullScale` (no default) to `describe().defaults.settings` as `[]` (a combined driver reads
its settings from `daq.<reg>`, so it is configured as `daq.<reg>.vppAtFullScale`), require it in
`checkConfig` in hardware mode, refuse levels above it in `checkLevel`, and convert in
`synthesize`: a sample of `s` full-scale units gives `s × vppAtFullScale / 2` volts, so the
volts of the plan are divided by `vppAtFullScale / 2` before they are played.

**`identity` and `metadata`** (2.2, 7). `identity()` returns what the instrument reported at
creation (no I/O). `metadata()` must be JSON-encodable and contain `driver`, `displayName`,
`roles`, `identity`, `sharedClock`, `settings` and the role settings in use (`maxVpp`, `load`;
for inputs `sampleRate`, `range`, `filter`, `ccld`, `teds`); it is stored with every measurement.

**`describe()`** (2.1). `name` = registry name; `displayName` (vendor, model and kind, shown in
the window and the metadata; at most about 50 characters, one line of the window's "In use" row,
which holds three lines for the two instruments); `labels.<role>` (short lamp label); `defaults.settings` (the driver
settings and their defaults, step 6); `defaults.acquisition` (DAQ: the values of
`acquisition.sampleRate`, `range`, `filter`, `ccld` when the configuration leaves them empty);
`texts.settle` (what settles after `prepare`, `sprintf` format with the filter, or `''`);
`texts.noun` and `texts.closed` (the window's sentences: "Connect the *noun* ...", "*noun*
*closed*", e.g. `'generator'`, `'output off'`); `simulation = 'protocol'` (the driver runs on the
real instrument, and in simulation mode on its protocol mock). `'only'` is for a driver that has no
real instrument - the demo of section 13, `simcombined` -: the registry then refuses it in hardware
mode, and its `fromConfig` raises `tim:instr:simulationOnly` there as well.

**`capabilities()`** (5). Every value from the manual, with its page in the reference document.
The window limits its fields with them and `checkConfig` refuses configurations outside them (at
Connect; loading a file only warns), so an optimistic value is a safety defect. `products`: the
MATLAB products the driver needs beyond MATLAB and the Signal Processing Toolbox, as
`struct('name', <name in ver>, 'feature', <licence feature>)`, e.g. `'Instrument Control Toolbox'` /
`'Instr_Control_Toolbox'`, `'Data Acquisition Toolbox'` / `'Data_Acq_Toolbox'`, `'Audio Toolbox'` /
`'Audio_System_Toolbox'`. Support packages and vendor runtimes that `ver` does not list are checked
by an optional static `checkInstalled()` (hardware mode, `tim:instr:missingProduct`);
`TemplateAcquisition` and `TemplateCombined` contain a commented skeleton for an NI device (the
NI-DAQmx support package and driver through `daqvendorlist`; check the call in the R2022b
documentation). Without it, a missing support package shows only later, as an undefined function
or a vendor error at Connect.

**`connectionSteps()`** (6). One `connect` step with the registry name as key; an acquisition
adds its `prepare` steps (the templates use `setup`). Keys must not repeat within a source /
acquisition pair and never be `sens`, `settle` or `signal` (the contract test checks it).

**`checkConfig(cfg)`** (9.2). Read the settings with `tim.instr.Instrument.settingsFrom`, check
each one (`tim:config:<what>`, the message names the key), then call the generic checks
(`tim.instr.SignalSource.checkSourceConfig`, `tim.instr.Acquisition.checkAcquisitionConfig`).
No I/O.

**`testHooks(obj)`** (11.3). Handles into the mock so that the contract tests can see the
instrument from outside the driver: `traffic`, `breakLink`, and for a source `outputOn`,
`levelHistory`, `forceOutputOn`, `forceLevel` (optional), `injectError`; for an acquisition
`stallAfter`, `injectChannelFault`, `isRecording`; for a combined block device also `outputLog`
and `playedSignal`. The templates have them all.

Never touch `tim.app.MeasurementSession`, `tim.gui.Tubebench` or any other file of `+tim/+gui`,
`+tim/+app`, `+tim/+cal`, `+tim/+dsp`, `+tim/+acoustics` for a new driver. If the driver seems to
need such a change, stop and ask the owner: either the contract is missing something (that is a
change of the contract, with its own review) or the driver is doing the session's job.

### 4.1 The device session of a combined device (NI-DAQmx, audio interface)

`TemplateCombined` talks to its device only through `obj.Dev`. For the hardware you write
`+tim/+instr/<Name>Session.m`: a handle class with exactly the methods of the template header
around the vendor interface. It is the only file that calls the product (`daq`,
`audioPlayerRecorder`), and only inside its methods, so the class loads without the product. What
each method must guarantee:

| Method | Must |
|---|---|
| `identify()` | read only; vendor, model, serial number, firmware as the device reports them |
| `configure(c)` | inputs (IEPE current, coupling, range) and the output channel; set the rate and return the rate the device **really** runs at (read back - a device may coerce it) |
| `start()` | start playing (zeros first) and recording |
| `playRecord(x)` | play the block `x` and return the input block recorded at the same samples, or with a fixed, known lag (below); never wait longer than the time-out |
| `stop()` | stop output and inputs **at once** |
| `writeZero()` | the output at 0 V now, in every state - also after `stop()` |
| `close()` | release the device; never throws |
| `setTimeout(t)` | the time-out of every wait [s] |

**NI device (Data Acquisition Toolbox).** One `DataAcquisition` (`daq("ni")`) with the four inputs
(`addinput`, measurement type `"IEPE"`, the excitation current and AC coupling) and the output
(`addoutput`, `"Voltage"`) runs both on one clock. Look up every call and property in the R2022b
documentation (`daq`, `addinput`, `addoutput`, `Rate`, `preload`, `start`, `write`, `read`, `stop`,
`flush`, `NumScansQueued`) and enter each in the reference document with its page. What the device
session has to solve:

* **The output is queued ahead.** In continuous mode the output is preloaded before `start`, and
  `write` queues more while the device runs; `read(d, m)` returns the next m recorded scans. When
  `playRecord` queues block j, the device still plays a block queued P calls earlier, so the scans
  `read` returns were recorded while that earlier block played: the input block lags the block
  `playRecord` was given by the queue (P blocks of B samples). Keep P small and constant and write it down: the excitation then lies P·B samples
  later in the record than planned, which the pre- and post-roll must cover (at 16 384 S/s, B =
  2048 and P = 2: 0.25 s; the default pre- and post-roll are 1 s), and `tim.dsp.detectExcitation`
  and the sweep gate check it after every measurement. At the normal end, read the queued blocks
  (the end of the fade and zeros) before `stop`.
* **Stop.** Queued samples cannot be faded any more. `outputOff` during the execution therefore
  stops the device at once (`stop`, then `writeZero`) and `acquire` ends with
  `tim:instr:outputStopped` (contract section 8.3): change `haltOutput` so - the one change of the
  engine for such a device - and keep the contract cases green (the mock has no queue).
* **Underrun.** When `onBlock` (the window's live view) takes longer than the queue, the output
  runs out of samples, the device reports an error and `acquire` ends with it; the engine then
  stops the device and writes 0 V (`endOutput`). A longer queue avoids it at the cost of the lag.
* **0 V after the stop.** An NI analog output can keep its last value after `stop` and after the
  device is released (contract section 3.1), so `writeZero()` must set 0 V on demand while the
  device is stopped (a single-scan write; check in the documentation of `write` what your device
  supports), and step 10 measures it at the output terminal.
* `readwrite(d, x)` (foreground) plays and records one block per call but runs a separate finite
  acquisition each time: the output idles between blocks and the record has gaps - not usable.

**Audio interface (Audio Toolbox).** `audioPlayerRecorder` plays one frame and returns the frame
recorded meanwhile (an ASIO driver on Windows); its round trip of a few milliseconds is the lag
(contract section 3.3). Levels are in full-scale units (`levelKnown = false`, `vppAtFullScale`;
inputs `dataUnit 'FS'` unless their volts per full scale are measured). Check at the output
terminal what the output does after a stop and after `release`.

The device session runs for the first time in step 10 (the mock replaces it in simulation), so
step 9 checks it with the Code Analyzer and loads its class, and step 10 (a) starts with the
loudspeaker disconnected.

## 5. Write the protocol mock

The protocol mock is the instrument in software. It has the same methods as the object the
driver talks to on the hardware (the transport or the device session), understands exactly the
commands the driver sends, and does what the manual says the instrument does - including the
errors it reports for a wrong value, an unknown command or a wrong state. In simulation mode the
driver runs on it unchanged, so the whole program, the contract tests and the window can be tested
without the instrument. A mock that accepts everything proves nothing: emulate the documented
side effects that the driver depends on (e.g. "a trigger is ignored unless the trigger source is
BUS").

It couples to the virtual tube (`tim.sim.SimulatedRig`, contract section 10) in one of three ways:

| The instrument | The mock | Example |
|---|---|---|
| a separate generator (own clock) | maps its state onto the rig's function-generator model, `rig.setGeneratorState(struct('OUTP', 0/1, 'FUNC', 'SIN'/'NOI', 'FREQ', Hz, 'VOLT', Vpp, 'FREQ_STAR', Hz, 'FREQ_STOP', Hz, 'SWE_SPAC', 'LOG'/'LIN', 'SWE_TIME', s, 'SWE_STAT', 0/1, 'TRIG_SOUR', text))`, after every change; `rig.generatorTrigger()` when the sweep starts; `rig.finishSweep()` before it answers that the sweep is complete (the virtual time runs to the end of the sweep) | `MockTemplateSource`, `MockScpiTransport` |
| a separate DAQ | takes the microphone voltages from `rig.generate(m)` (m x 4, whatever source drives the rig); while it runs it registers a function that produces its next block, `rig.setProducer(@() obj.advance())` (`[]` at stop and close), used by `finishSweep` | `MockTemplateAcquisition`, `MockLanXiStream` |
| one device in both roles | gives the rig its output samples and records the answer, `y = rig.respond(x)`; 0 V is `rig.respond(zeros(0, 1))` | `MockTemplateCombined`, `SimulatedCombined` |

Keep from the template: the `Log` of every command (the contract tests count it to check that
nothing is sent after `close()`, and that `AbortFcn` comes before any stop request - so a failing
operation raises **before** it is logged, and data reads of a stream are not logged), the fault
injection used by `testHooks`, and the line to `tim.instr.mockBusLog` (it records the traffic of a
simulated session when a test asks for it). The mock never calls a product function: the tests
must run on any PC with MATLAB and the Signal Processing Toolbox.

## 6. Settings, defaults and configuration

* The driver's own settings (address, port, time-out, ...) and their defaults are in
  `describe().defaults.settings`; the configuration holds them in a sub-struct named after the
  registry name (`generator.<reg>` or `daq.<reg>`; a combined driver uses `daq.<reg>`). The
  registry merges the configured values onto these defaults (`ctx.settings`). Do **not** add
  them to `tim.app.defaultConfig` (it holds only the default drivers' sub-structs) - a new
  generic setting that every driver would use is a change of the contract and needs the owner.
* A default address is never a real instrument's: use the documentation address `192.0.2.10`
  (RFC 5737), which no device has. A device chosen by name (an NI device, an audio interface) gets
  no default (`''`), and `checkConfig` requires the name in hardware mode, as
  `TemplateAcquisition` and `TemplateCombined` do: `Dev1` is the name NI-DAQmx gives the first
  device, so a default `Dev1` would open whatever device happens to be there.
* The generic settings (`generator.maxVpp`, `generator.load`, the `acquisition` and `excitation`
  sections) stay where they are; the driver only limits their values (`capabilities`,
  `checkConfig`). A DAQ driver gives the defaults of the inputs in `describe().defaults.acquisition`;
  a configuration file that leaves `acquisition.sampleRate`, `range`, `filter`, `ccld` out takes
  them. A configuration built in code keeps the LAN-XI values of `tim.app.defaultConfig`: set
  them empty and call `tim.app.migrateConfig(cfg)` (as the test templates do).
* Make your own configuration file for the new driver, from a configuration of `formatVersion` 2
  (`config/sim_thin_screen.json`; or load the lab file and save it in the new layout:
  `cfg = tim.app.loadConfig('config/user_config.json'); tim.app.saveConfig(cfg, 'config/<instrument>.json')`),
  and put the section of your role from `templates/instrument/config_snippet.json` into it
  (`generator` for a source, `daq` for an acquisition) or, for a combined driver, both sections
  of `config_snippet_combined.json` (it names itself in both and keeps its settings in
  `daq.<reg>` only; settings in `generator.<reg>` are not read and give the warning
  `tim:config:misplacedSettings`), with your driver's names and settings.
  Use `"mode": "simulation"` until step 10. **Do not change `config/user_config.json`**: it is
  the owner's lab file; switching it to a new driver is the owner's decision after step 10. Your
  configuration file is a working file: commit it only if the owner wants it in `config/`.

## 7. Write the protocol reference

Copy `templates/instrument/ref_template.md` to `docs/ref_<instrument>.md` and fill it in: the
manual (title, publication number, edition, where it came from), the identification as read from
the real instrument (only with the owner, step 10a; until then "not read yet"), the interface,
**every command and reply format the driver and the mock use with its manual section and page**,
every limit of `capabilities()` with its source, what the driver does because of the manual, every
item the manual does not state (marked **NOT VERIFIABLE**; the driver must not rely on it), and
the suitability table of step 2. `docs/ref_33220A_scpi.md` is a finished example.

## 8. Register the driver

Add one entry to the list in `+tim/+instr/drivers.m` (name and class, in the same order):

```matlab
list = struct( ...
    'name',  {'keysight33220a',           'lanxi',           'simcombined',               'demo'}, ...
    'class', {'tim.instr.Keysight33220A', 'tim.instr.LanXi', 'tim.sim.SimulatedCombined', 'tim.instr.DemoSource'});
```

Check: `d = tim.instr.driverInfo('<reg>')` shows the description, the capabilities and the
steps, without an error. To try a driver before its line is added:
`tim.instr.drivers('add', struct('name', '<reg>', 'class', 'tim.instr.<Name>'))` (this MATLAB
session only).

## 9. Test offline

Everything in this step runs in simulation; no instrument is contacted.

1. **No placeholder left**: the `Select-String ... -Pattern 'TODO'` of step 3 finds nothing.
2. **Code Analyzer**: `checkcode('+tim/+instr/<Name>.m')` (and the mock, the test and the
   device session `<Name>Session.m` of section 4.1): no message except the "extra comma" of
   one-line `try, ...; catch, end` (the project's style). The device session runs only on the
   hardware, so also load its class: `meta.class.fromName('tim.instr.<Name>Session')` returns the
   class without an error, also on a PC without the product.
3. **Driver tests**: `addpath(pwd); runtests('tests/Test<Name>.m')`. Adapt the copied tests to
   your instrument's facts (the `TODO` lines); add a test for every particular rule of the manual
   that the driver relies on (an order of commands, a reply format, a refusal).
4. **Contract tests**: `runtests('tests/TestInstrumentContract.m')` runs every case for every
   registered driver, including yours; each failure names the duty (section 11 of the contract).
   Fix the driver, not the test.
5. **Full suite** (about 15-20 minutes), in a separate MATLAB from PowerShell so that your MATLAB
   stays free:

   ```powershell
   $code = "r = run_tests(); assertSuccess(r)"
   $log  = "$env:TEMP\tubebench_tests.log"
   $p = Start-Process -FilePath "C:\Program Files\MATLAB\R2022b\bin\matlab.exe" -ArgumentList @('-sd', "`"$PWD`"", '-batch', "`"$code`"", '-logfile', "`"$log`"") -Wait -PassThru -WindowStyle Hidden
   $p.ExitCode; Get-Content $log -Encoding UTF8 | Select-Object -Last 40
   ```

   Exit code 0 and no failed test. `tests/last_test_report.txt` lists every test.
6. **Nothing outside the driver changed**: `git status` and `git diff --stat` list only your new
   files and the one line in `+tim/+instr/drivers.m` (plus documentation). In particular no change
   to `+tim/+app/MeasurementSession.m`, `+tim/+gui/Tubebench.m` or any other file of `+tim/+gui`.
7. **The window in simulation**: `tubebench config/<instrument>.json` (with `"mode":
   "simulation"`). The INSTRUMENTS section shows your lamp label and display name, Setup >
   Connection your checklist steps and, after Connect, the identity your mock reports with
   "(simulated)". Make a calibration and a measurement on the virtual tube.

## 10. Verify on the hardware

Only after step 9 is complete. **Each step only with the owner present and agreeing to that
step**; tell the owner before each step what will happen and what could go wrong. Stop at the
first surprise: output off (`s.Gen.outputOff()`), `s.close()`, report to the owner. Results go
into `docs/hardware_status.md` (step 11) - a step counts as passed only with a real measurement.

Preparation (owner): the instrument connected and switched on, its address set by the owner (never
change it), the loudspeaker connected only from step (c) on, an amplifier at minimum gain, and a
copy of your configuration file with `"mode": "hardware"` and a conservative `generator.maxVpp`:
no higher than the level the owner approves (the default excitation level is 0.2 Vpp; the default
`generator.maxVpp` of `tim.app.defaultConfig` is 0.5 Vpp, the lab file's 2 Vpp). The other role keeps its
lab instrument (33220A or LAN-XI) unless your driver takes both roles.

**(a) Connect and identify, output off.**

```matlab
cfg = tim.app.loadConfig('config/<instrument>_hw.json');
s = tim.app.MeasurementSession(cfg);
s.connect();                                   % the drivers' checklist steps; output off
disp(s.Gen.identity()); disp(s.Daq.identity())
s.Gen.isOutputOn(1)                            % generator: false (read back)
s.close();
```

Pass: the identity is the real model, serial and firmware (enter it in the reference document);
the output is off - read back **and** seen at the instrument (front panel / output LED); after
`close()` the instrument is idle and the output is still off; no error in the command window.
For an analog or audio output (no relay), "seen at the instrument" means a voltmeter (DC) at the
output terminal, with the loudspeaker and amplifier disconnected: 0 V after `connect` and after
`close()`.

**(b) Acquisition with the output off.**

```matlab
s = tim.app.MeasurementSession(cfg); s.connect(); s.prepareAcquisition();
r = tim.val.testA_acquisition(s, 2)            % integrity, flags, background level
s.close();
```

Pass: `r.passed` true (no fatal integrity problem, no device flag, the configured sample rate);
the background level is plausible for the room (the lab: about 47-64 dB SPL, 100-5000 Hz); for
a new generator: no tone of the generator in the record (its output is off). For a new DAQ also
check the channel order (`tim.val.channelIdentification(s)`, the procedure of
`docs/validation_procedure.md`, Test A).

**(c) Lowest-level excitation into the tube.** The owner states the level (start at the
instrument's smallest useful level, e.g. 0.05 Vpp, never above the configured default 0.2 Vpp
without the owner's decision) and stays at the amplifier. Ask before every increase. In hardware
mode the session asks before it drives the loudspeaker (level and amplifier gain, and the
loudspeaker power limit): answer only after the owner has agreed, and record the amplifier and
its gain first (`s.setAmplifierGain(model, gain)`, as in `examples/hardware_commissioning.m`).

```matlab
s = tim.app.MeasurementSession(cfg); s.connect(); s.prepareAcquisition();
r = tim.val.testB_singleFrequency(s, 1000, 0.05, 1)   % 1 kHz sine, 0.05 Vpp, once
t = tim.val.sweepTimingTest(s)                         % the configured sweep inside the record
s.close();
```

Pass: the tone is in the record on every channel, no overload; after each measurement the output
is off (read back and at the instrument); the sweep lies inside the record with margins. Then in
the window (`tubebench config/<instrument>_hw.json`): start a measurement and press **Stop** -
the output goes off at once and the window says so; start one again and close the window - the
output goes off. For an analog or audio output, measure 0 V DC at the output terminal (voltmeter,
before the amplifier) after the Stop, after closing, and after a measurement that ended with an
error: an analog output that keeps its last value would put a DC voltage on the voice coil. (When
the link to the device itself is lost, no program can set 0 V: with the loudspeaker disconnected,
note what the output does then and report it to the owner.)

**(d) Switching calibration and Test E.** As in `docs/calibration_procedure.md` (empty specimen
section, the geometry measured and entered):

```matlab
s = tim.app.MeasurementSession(cfg); s.connect(); s.prepareAcquisition();
[cal, calFile] = tim.app.runCalibration(s);   % operator steps; ends with the empty-tube check (Test E)
cal.meta.emptyCheck                           % passed true
s.close();
```

Pass: the calibration completes and Test E passes (criteria in `docs/validation_procedure.md`).

## 11. Document and commit

* `docs/hardware_status.md`: one row per verified function (date, what, result, data folder),
  **SW-VERIFIED** after step 9, **HW-VERIFIED** only for the steps of step 10 that passed on
  the real instrument; the others stay **PENDING**.
* `docs/ref_<instrument>.md` (step 7), the real identification after step 10a.
* `docs/user_guide.md` section 9 (Choosing the instruments): the driver in the list of drivers.
  `docs/installation_windows.md` section 1.1: what the driver needs. `README.md`: the supported
  instruments, the structure section if a new kind of file was added, and the test count.
  `docs/instrument_interface.md`: the driver in the tables of sections 5 (capabilities) and 6
  (connection steps).
* Commit in logical steps (the driver with its mock and tests; the documentation; each hardware
  result), adding the files by name - never `git add -A` (it would add data or private files).
  Never commit `data/`, `calibration/` or `cad/`. **Never push** unless the owner asks.
* Report to the owner: the suitability table, the files added or changed, the test results, and
  which hardware steps were verified on the real instrument and which were not.

## 12. Safety rules

These hold in every step, for a person and for Claude Code alike.

1. **Simulation first.** No instrument is contacted before step 9 is complete. Configurations for
   development have `"mode": "simulation"`; the lab file `config/user_config.json` is not changed.
2. **Never guess a command.** Every command, reply format and limit comes from the manual and is
   entered with its page in `docs/ref_<instrument>.md`. If the manual does not state it, the
   driver does not rely on it.
3. **Hardware steps only with the owner present and agreeing** - each of the four steps of section
   10 separately.
4. **No change** of IP addresses, firewall settings, firmware, licences or drivers (vendor
   software) without the owner's approval.
5. **Ask before raising an excitation level** - every time, also between repetitions; never above
   the configured default 0.2 Vpp without the owner's decision.
6. **Output off first**: on connect, before every setting, after every error, on Stop, on close.
   At the end of every hardware step, check the output at the instrument.
7. **Raw data are never modified**: measurement folders under `data/` and calibration files are
   only read; reprocessing writes a new folder.
8. **No clicking or typing on the owner's screen**; the owner's MATLAB session and windows stay as
   they are. Run tests in a separate MATLAB (section 9, step 5). Whoever works on the owner's PC
   without being the owner (a helper, Claude Code) opens windows only hidden or in a MATLAB
   process of their own, never in the owner's session.
9. **Commit, never push** unless the owner asks; add files by name.
10. **Never mark a hardware step passed without a real measurement** (`docs/hardware_status.md`).

## 13. Worked example: the demo source

The demo source was added on 2026-10-11 by following this guide literally (the dry run of WO-001
Part 2). It is **simulation only**: the DEMO-SG1 signal generator does not exist, and
`docs/ref_demo_source.md` defines its commands and plays the part of its programming manual. It
stays registered as the worked example, so the contract tests keep checking it.

| Step | What was done |
|---|---|
| 1 Facts | DEMO-SG1, one channel, generator only; SCPI over TCP port 5025 with channel-numbered headers (`SOUR1:`, `OUTP1:`, `TRIG1:`); output state reply `ON` / `OFF`; no load setting, no amplitude unit command, no noise; manual: `docs/ref_demo_source.md` |
| 2 Suitability | every generator Must met (off by command with read-back, level limit in the driver, LOG sweep 0.1 Hz-100 kHz); noise not available (optional); table in the reference, section 6 |
| 3 Copy | the snippet of section 3 with `from = 'TemplateSource'`, `name = 'DemoSource'`, `reg = 'demo'`: `+tim/+instr/DemoSource.m`, `+tim/+instr/MockDemoSource.m`, `tests/TestDemoSource.m` |
| 4 Driver | every `TODO` replaced: the DEMO-SG1 commands with their section of the reference; the output state parsed as `ON` / `OFF`; the load and unit commands deleted (`loads` = `{'INF'}`); `configureNoise` reduced to the refusal; limits from the reference; `simulation = 'only'` and a `fromConfig` that refuses hardware mode |
| 5 Mock | the command set of the reference (header parser with digits for the channel numbers), the error queue of 16 entries, the replies `ON` / `OFF`; coupled to the rig through `setGeneratorState` (sine only) and `generatorTrigger` |
| 6 Settings | `generator.demo`: `host` (the documentation address, never used), `port`, `timeout`; a configuration file made from `config/sim_thin_screen.json` with the `generator` section of the snippet (`"driver": "demo"`) |
| 7 Reference | `docs/ref_demo_source.md` from `ref_template.md` |
| 8 Registry | `'demo'` / `'tim.instr.DemoSource'` in `+tim/+instr/drivers.m` |
| 9 Tests | no `TODO` left; Code Analyzer: only the "extra comma" messages of the one-line `try`; `tests/TestDemoSource.m` (6 tests, one added for the refused noise); `tests/TestInstrumentContract.m`: every case for `demo` (and the hardware-mode refusal of a simulation-only driver); full suite green; `git diff --stat`: only the new files and the registry line - no change to the session or the window; in the window (simulation) the lamp "Generator", the display name, the checklist step "Demo generator DEMO-SG1 (SCPI, simulated)", the amplitude limits 0.001-0.25 Vpk (its 2 mVpp minimum, `maxVpp` 0.5) and sweep times 0.01-300 s, after Connect "Generator: DEMO-SG1 s/n DEMO-0001 (simulated)", a calibration with Test E passed and a measurement with the output off afterwards |
| 10 Hardware | does not apply: there is no instrument (the registry refuses the driver in hardware mode) |
| 11 Documents | this section; the driver lists of the user guide, the installation guide, the README and `docs/instrument_interface.md` |

To see it in the window (simulation; the lab configuration files stay unchanged):

```matlab
cfg = tim.app.loadConfig('config/sim_thin_screen.json');
cfg.generator.driver = 'demo';
f = fullfile(tempdir, 'sim_demo.json'); tim.app.saveConfig(cfg, f);
tubebench(f)
```

The dry run changed this guide and the templates where they were unclear or wrong: the copy
snippet makes sure the project is on the path and also renames the capitalised names of the help
lines; the template paragraph of each help text has to be replaced (it contains "TODO"); a
function the instrument lacks is reduced to its refusal (its command lines would otherwise keep
their `TODO`s); `simulation = 'only'` for a driver without a real instrument; the configuration
file takes only the section of the driver's role; the mock template accepts channel numbers in
command headers; the step numbers cited in the template headers. The acquisition and combined
templates have no worked example of their own; `tests/TestInstrumentTemplates` runs them, with
their driver tests, through the contract tests on their mocks.

## 14. Checklist

1. [ ] Fact sheet filled in; the manual at hand (section 1).
2. [ ] Suitability table: every Must item met, with manual pages (section 2).
3. [ ] Templates copied and renamed (section 3).
4. [ ] Driver written; no `TODO` left (section 4); for a combined device its device session
   (section 4.1).
5. [ ] Protocol mock written; no `TODO` left (section 5).
6. [ ] Defaults in `describe()`; own configuration file in simulation mode (section 6).
7. [ ] `docs/ref_<instrument>.md` with a source for every command (section 7).
8. [ ] One line in `+tim/+instr/drivers.m` (section 8).
9. [ ] Driver tests, contract tests and the full suite green; no change outside the driver; the
   window in simulation (section 9).
10. [ ] With the owner: (a) identify, output off; (b) acquisition, output off; (c) lowest level;
    (d) calibration and Test E (section 10).
11. [ ] `docs/hardware_status.md` and the other documents updated; committed, not pushed
    (section 11).
