---
name: add-instrument
description: Connect an instrument that tubebench has no driver for - a signal generator, an acquisition module (DAQ), an NI DAQ device or an audio interface - by running docs/adding_an_instrument.md step by step with the owner, from the programming manual and the suitability check to the driver, its protocol mock and tests, and the hardware verification. Use when the owner wants to use a new generator or DAQ, asks whether an instrument is suitable, or asks for a new instrument driver.
---

# Add an instrument

The procedure is `docs/adding_an_instrument.md`. This skill only runs it: it holds nothing the
guide lacks, and where the two differ the guide is right. The contract a driver implements is
`docs/instrument_interface.md`.

## Procedure

1. **Read** the guide completely, and the contract sections it names (1-5, 8, 11).
2. **Ask the owner for the instrument's programming manual** (PDF). Without it, stop: commands are
   never guessed. Fill in the fact sheet of guide section 1 from the manual and from the owner.
3. **Judge suitability** (guide section 2): every Must and Should item of the role(s), with the
   manual page. Show the table to the owner. If a Must item fails, stop and say why and what would
   work instead.
4. With the owner's go-ahead, **steps 3-8**: copy the templates, write the driver and the protocol
   mock (every instrument fact from the manual, no `TODO` left), defaults in `describe()`,
   `docs/ref_<instrument>.md` with a source for every command, one line in the registry.
5. **Step 9, offline tests**: driver tests, contract tests, the full suite - in a separate batch
   MATLAB, never in the owner's MATLAB session (CLAUDE.md, Commands); `git diff --stat` shows no
   change outside the driver; the window only in simulation and only hidden or in a MATLAB process
   you started yourself.
6. **Step 10, hardware**: the four steps (a) identify with the output off, (b) acquisition with the
   output off, (c) lowest-level excitation into the tube, (d) switching calibration and Test E -
   one at a time. **Before each step** say what will happen, and ask the owner for approval and
   presence; wait for the answer. At the first surprise: output off, `s.close()`, report.
7. **Step 11**: `docs/hardware_status.md` (HW-VERIFIED only with a real measurement) and the other
   documents; commit; report to the owner what was done, tested and verified, and what not.

## Rules (WO-001 section 5; guide section 12)

* No change of IP addresses, firewall, firmware, licences or drivers without the owner's approval.
* Ask before raising an excitation level - every time.
* Raw data are never modified.
* Output off first.
* No clicking or typing on the owner's screen.
* Commit (files added by name), never push unless the owner asks.
* Simulation first; never guess a command; hardware steps only with the owner present and
  agreeing; never mark a hardware step passed without a real measurement.
