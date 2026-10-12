# Windows installation and set-up guide (tubebench)

## 1. Summary: what is required

| Component | Required? | Status on the lab PC (checked 2026-10-08) |
|---|---|---|
| Windows 10/11 (64-bit) | yes | Windows 11 Education 10.0.22631 |
| MATLAB R2022b | yes | **R2022b Update 2** (9.13.0.2105380) installed |
| Signal Processing Toolbox | yes (`pwelch`, `cpsd`, `butter`, `filtfilt`, `spectrogram`, `hann`, `freqz`) | installed |
| Instrument Control Toolbox | **not strictly** (see below), recommended | installed |
| NI-VISA / Keysight IO Libraries | **no** | not needed (raw TCP socket) |
| NI-DAQmx, Data Acquisition / Audio Toolbox | **no** for today's drivers | not used (the lab DAQ is the HBK LAN-XI); only a driver that declares them needs them (section 1.1) |
| HBK BK Connect / LAN-XI drivers / SDK | **no** | not needed (Open API = HTTP + TCP) |
| Python, Java, C++ runtimes | **no** | – |
| Git | optional (version control) | **Git for Windows 2.55.0** installed 2026-10-08 (see section 6) |

The software needs **no additional drivers, SDKs, runtimes or add-ons**:

* The 33220A is driven by SCPI over a raw TCP socket (port 5025) using MATLAB's `tcpclient`.
  `tcpclient` is part of base MATLAB since R2014b, and `writeline`/`readline` since R2020b. The
  Instrument Control Toolbox is therefore not strictly required, though it was available during
  development.
* The LAN-XI is driven by HTTP REST (`matlab.net.http`, base MATLAB) plus a TCP data socket
  (`tcpclient`). This is the documented LAN-XI Open API (BE 1872). The module's firmware
  2.10.0.610 is newer than 2.10.0.344, which HBK requires for license-free Open API use.
* `matlab.unittest` (tests) and `uifigure` (GUI) are part of base MATLAB R2022b.

Verify the toolboxes in MATLAB:

```matlab
ver                                  % lists installed products
license('test', 'Signal_Toolbox')    % must return 1
exist('tcpclient')                   % must return 2 (or 8)
```

### 1.1 Instrument drivers and what they need

The configuration chooses the instruments by driver name (`generator.driver`, `daq.driver`; user
guide section 9). What a driver needs beyond MATLAB and the Signal Processing Toolbox:

| Driver | Role | Needs in addition | Modes |
|---|---|---|---|
| `keysight33220a` | generator (Keysight/Agilent 33220A, SCPI over TCP) | nothing (`tcpclient`, base MATLAB) | hardware; simulation on its protocol mock |
| `lanxi` | acquisition (HBK LAN-XI, Open API) | nothing (`matlab.net.http`, `tcpclient`, base MATLAB) | hardware; simulation on its protocol mock |
| `simcombined` | both (simulated device: one output, four inputs, one clock) | nothing | simulation only |
| `demo` | generator (the imaginary DEMO-SG1, worked example of `docs/adding_an_instrument.md`) | nothing | simulation only |

A driver added later (`docs/adding_an_instrument.md`) declares the MATLAB products it needs (e.g.
the Data Acquisition Toolbox for an NI DAQ, the Audio Toolbox for an audio interface) in its
capabilities, and may check support packages or vendor runtimes (NI-DAQmx, an ASIO driver)
itself. In hardware mode Connect
checks them **before any instrument is contacted** and names the missing product and the driver
(`tim:instr:missingProduct`); simulation mode and the automated tests need none of them, so they
run on any PC with MATLAB and the Signal Processing Toolbox. To see what a driver needs:

```matlab
tim.instr.drivers()                                  % registered drivers
d = tim.instr.driverInfo('lanxi'); d.capabilities.products   % empty = nothing beyond the base
```

## 2. Network

Both instruments use **link-local (169.254.x.x) addresses** and answered from this PC:

| Instrument | IP | Port(s) | Verified |
|---|---|---|---|
| 33220A | 169.254.2.20, **static** since 2026-10-12 (DHCP off, Auto IP off, mask 255.255.0.0) | TCP 5025 (SCPI socket) | ping, `*IDN?` |
| LAN-XI 3676 | 169.254.64.156 | TCP 80 (REST), TCP data port reported by `/rest/rec/destination/socket` (typically 1536) | ping, REST, streaming |

Nothing was changed on the PC (network adapters, firewall) or in the instrument firmware. The
connection runs PC (USB Ethernet adapter, automatic 169.254.x.x address) → switching hub → 33220A
and LAN-XI. On 2026-10-12 the owner set the 33220A from DHCP + Auto IP to a static IP with the
same address (Utility → I/O → LAN → Modify Settings): with DHCP on and no DHCP server, the
instrument had dropped idle SCPI connections now and then (docs/hardware_status.md, hardware check
of 2026-10-12, observation 1). The static IP did not stop it (an idle probe on one socket dropped
after 5 min, 15:21-15:26); it is kept, as the address can no longer change by itself. Since 1.2.1
the program replaces idle connections and re-opens dropped ones by itself.

Possible issues and remedies (each requires **your** decision; the software never changes them):

* **Windows Firewall** blocks MATLAB: Windows asks the first time MATLAB opens a connection. Allow
  MATLAB on the network profile of the instrument adapter. Only outgoing connections are used; no
  inbound rule is needed.
* **Several network adapters with link-local addresses** (e.g. Wi-Fi plus the instrument switch):
  if connections become intermittent, give the instrument adapter a static address in a dedicated
  subnet. This would also change the instruments' addresses and needs your explicit approval.
* **LAN-XI already in use**: only one Open API client at a time. Close BK Connect / PULSE.
  According to the Open API manual a power cycle may be needed after BK Connect has used the
  module.
* **33220A holds one socket session**: close other programs (Keysight IO, web control) that may
  hold port 5025.

## 3. Installing this software

1. Clone the repository (section 6) or copy the project folder `tubebench` to any location,
   e.g. `C:\Users\<you>\Desktop\wj\tubebench`. Do not rename the `+tim` folder.
2. Start MATLAB R2022b, `cd` into the folder and run `addpath(pwd)` (done automatically by
   `start_here.m` and `run_tests.m`). The `+tim` package needs only the project root on the path.
3. Check `config/user_config.json` (lab settings, part of the repository; see the user guide).
   On a set-up other than the lab tube, create it from `config/example_config.json`.
4. Start the program: double-click `start_tubebench.bat` in the project folder, or type
   `tubebench` (`tubebench sim`: virtual tube for practice) in MATLAB (the old names
   `start_tubeapp.bat` and `tubeapp` were removed on 2026-10-11). `start_tubebench.bat` starts
   MATLAB without its desktop (`-nodesktop -nosplash`: about 1.5 s faster, and the program window
   is the only large window). A small MATLAB command window stays open behind the program; closing the program
   leaves it open (MATLAB is not quit automatically): type `tubebench` there to open the program
   again, and `exit` (or close that window) to quit MATLAB. Help > User guide still opens the
   documents in the MATLAB Editor. The main window appears about 16 s after the double-click; the
   other views are prepared in the background (user guide, section 2).

## 4. Verification

```matlab
cd <project folder>
results = run_tests();          % ~15–20 min, simulation only; report in tests/last_test_report.txt
```

All tests must pass. Then, in hardware mode, run section H0/H1 of
`examples/hardware_commissioning.m`. The instruments are identified and 2 s of data are acquired
without excitation.

Network-only check from PowerShell (read-only):

```powershell
Test-Connection 169.254.2.20 -Count 2
Test-Connection 169.254.64.156 -Count 2
Invoke-WebRequest -UseBasicParsing http://169.254.64.156/rest/rec/onchange
```

## 5. Compatibility notes

* Developed and tested with MATLAB **R2022b Update 2** on Windows 11. Functions used: `arguments`
  blocks (R2019b+), `tcpclient` with `writeline/readline/configureTerminator` (R2020b+),
  `exportgraphics` (R2020a+), `uigridlayout` (R2018b+), `matlab.net.http` (R2016b+).
  `jsonencode(...,'PrettyPrint',true)` needs R2021a+.
* MATLAB's `fileread` uses the system code page (CP949 on Korean Windows). JSON files are therefore
  read with an explicit UTF-8 reader (`tim.app.readTextUtf8`).
* MATLAB warns "PUT/POST message should have a body" for the body-less Open API commands. That
  specific warning (`MATLAB:http:BodyExpectedFor`) is silenced inside the HTTP client.
* The LAN-XI Open API reference implementation by HBK (MATLAB, MIT licence) was developed with
  firmware 2.10.0.501. This project re-implements the protocol and was tested against 2.10.0.610.

## 6. Git (optional, for version control)

Git is not needed to run the software; it keeps the history of the code and of the lab
configuration, and its commit is stored with every measurement and calibration.

* **Lab PC**: Git for Windows **2.55.0** is installed (2026-10-08) in `C:\Program Files\Git`;
  `C:\Program Files\Git\cmd` is on the system PATH, so `git --version` works in every terminal
  opened after the installation (a terminal that was already open needs
  `"C:\Program Files\Git\cmd\git.exe"`).
* The project folder is a repository on branch `main` (first commit 2026-10-08). Repository:
  <https://github.com/kimwoongji/tubebench> (private; not created yet). No remote is configured on
  the lab PC yet; creating the GitHub repository under this name, adding it
  (`git remote add origin <url>`) and pushing are left to the owner.
* Daily use, in the project folder:

  ```
  git status                        # what changed (code, docs, config/user_config.json)
  git add -A
  git commit -m "what and why"      # before measuring with edited code or configuration
  git log --oneline -10             # history
  ```

* What is versioned: code, tests, docs, `config/*.json` including `user_config.json` (lab
  settings and geometry). What is **not** versioned (`.gitignore`): measurement data (`data/`),
  calibration files (`calibration/**/*.mat`), the CAD models (`cad/`), test reports and MATLAB
  autosave files. Archive raw data separately.
* Another PC: install Git for Windows (https://git-scm.com/download/win, default options, or
  `winget install --id Git.Git -e`), then
  `git clone https://github.com/kimwoongji/tubebench.git` (needs access to the private
  repository; creates the folder `tubebench`).
* The program does not depend on the folder name. The project was called
  `transfer-impedance-tube-measurement` until 2026-10-10 (program and folder); measurements and
  calibrations saved before then name it and the old folder in their metadata (information only).
