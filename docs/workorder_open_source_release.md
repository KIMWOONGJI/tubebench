# Work order WO-002: open-source release (licence, citation, packaging, distribution)

| | |
|---|---|
| Target version | first public release (1.2.0 or later; may come before or after WO-001) |
| Status | planned - written 2026-10-10, not started |
| Requested by | the owner (Woongji Kim) |
| Blocking condition | **approval of the supervisor / institution** (see §2) before anything is made public |
| Not included | pushing or creating the GitHub repository - the owner does that (push is on hold) |

## 1. Goal

Publish tubebench as open-source MATLAB software that other labs can install, run, cite and
extend, with a clear licence and a reproducible release process.

Decisions recommended on 2026-10-10 (to be confirmed by the owner when this work starts):

- **Licence: BSD-3-Clause.** Permissive (use, change, redistribute, also commercially) with the
  copyright notice kept; the third clause forbids using the authors' or the institution's name to
  promote derived products without permission, which suits university software. Alternative:
  MIT (same freedom, no name clause). Not recommended: GPL-3.0 (copyleft; awkward for code that
  runs on proprietary MATLAB and for industrial users), Apache-2.0 (patent clauses not needed).
- **Distribution: source first.** (1) GitHub repository `kimwoongji/tubebench` with tagged releases
  (zip of the source); (2) a MATLAB app installer (`.mlappinstall`, installs into the APPS tab)
  attached to each release; (3) a MATLAB File Exchange entry linked to the GitHub repository.
  A standalone executable (MATLAB Compiler + free MATLAB Runtime R2022b) stays deferred
  (docs/assumptions_and_limitations.md, item 9) until users without MATLAB need it.

## 2. Before anything is published (owner)

1. **Ownership.** Software written in a university lab within a research project may belong to
   the university and/or be governed by the project agreement. Get the supervisor's approval and
   check the institution's rules (technology transfer / industry-academic cooperation office)
   and any project agreement. Record who approved, and when, in this file.
2. **Copyright holder** for the LICENSE line: the author, the lab, or the university - follows
   from step 1.
3. **Author e-mail in the history.** All 29+ commits carry `Woongji Kim <wj.kim@postech.ac.kr>`;
   publishing the history publishes that address. Keep it, or rewrite the history before the
   first push (`git filter-repo --mailmap`), owner's choice.
4. **Lab-specific configuration.** `config/user_config.json` holds the lab's instrument addresses
   (link-local 169.254.x), mics and geometry. Keep it as the lab's example, or replace it in the
   public repository by `example_config.json` and keep the lab file untracked.

## 3. Current state (checked 2026-10-10)

- Required products (`matlab.codetools.requiredFilesAndProducts`): **MATLAB R2022b and Signal
  Processing Toolbox** only. Instrument communication uses base MATLAB (TCP, HTTP).
- Never committed: `data/`, `calibration/`, `cad/` (checked over the whole history). Largest
  tracked file 0.25 MB (`tests/fixtures`, recorded from the lab's own LAN-XI module).
- Third-party material: the HBK `open-api-time-data-recorder` (MIT) and `open-api-tutorials`
  (Kaitai format description, no licence file) are used as behavioural/format references only,
  no code copied (docs/ref_lanxi_openapi.md). No manuals or datasheets are in the repository.
- Version and commit are written into every measurement (`tim.app.softwareVersion`); the commit
  comes from git and is unknown in an installed package without `.git`.
- No LICENSE, CITATION.cff or CHANGELOG yet. README says the repository is not created yet.

## 4. Tasks

1. **LICENSE** (BSD-3-Clause text, holder and year from §2); a "License" section in README; a
   one-line licence/copyright header in the main entry files only (`tubebench.m`,
   `+tim/+gui/TubeApp.m`) - not in every file.
2. **CITATION.cff** (title tubebench, authors with ORCID if available, version, date, licence,
   repository URL); a "How to cite" section in README; after the first GitHub release, connect
   the repository to Zenodo for a DOI per release and add the DOI badge.
3. **CHANGELOG.md** from the git history (grouped per version: 1.0 bench tests, 1.1 GUI and
   analysis review, 1.2 …); release notes per tag.
4. **Version stamping for packages.** A `tools/make_release.m` that (a) checks the working tree is
   clean and tests pass, (b) writes the commit hash into a tracked-at-build-time file (e.g.
   `+tim/+app/buildInfo.m` returning commit/date) that `softwareVersion` uses when `.git` is
   absent, (c) builds the app installer `tubebench.mlappinstall` (`matlab.apputil.package` with a
   `.prj`, main file `tubebench.m`, icon from `resources/logo`), (d) zips the source, (e) prints
   the checksums. The installed app must start the same way (`tubebench`, `tubebench sim`) and
   store config/data in a user folder when the project root is read-only (decide: Documents
   folder or next to the installation; same issue as the standalone item 9).
5. **README for the public:** what it measures, requirements (MATLAB R2022b+, Signal Processing
   Toolbox; for hardware: 33220A + LAN-XI 3676 until WO-001 adds drivers), install (clone / zip /
   app installer), simulation mode first (`tubebench sim`), screenshots (from `examples/output`),
   validation status (software-verified vs. hardware-verified, docs/hardware_status.md), licence,
   citation, contributing.
6. **CONTRIBUTING.md** (issues, tests must pass: `run_tests`, coding style of the repository,
   no raw data in commits) and a short **SECURITY/SAFETY note** (the program drives a loudspeaker:
   level limits, output-off rules).
7. **Repository hygiene:** `.gitattributes` (line endings: `*.bat` CRLF, others LF), check
   `.gitignore`, remove local-only notes (ONBOARDING.md stays untracked or becomes a public
   CONTRIBUTING section), a final secret/PII scan of the tree and history (IP addresses, e-mail,
   paths with user names such as `C:\Users\Rholab`).
8. **File Exchange:** after the GitHub release, create the File Exchange entry linked to the
   repository (it follows GitHub releases); fill in the product requirements.
9. **Optional later:** standalone application (see item 9 of assumptions_and_limitations.md;
   MATLAB Compiler is licensed but not installed), MATLAB Online "Open in MATLAB Online" badge.

## 5. Acceptance

- LICENSE, CITATION.cff, CHANGELOG.md present; README sections updated; all tests pass.
- `tools/make_release.m` produces the installer and the zip from a clean tree; installing the
  `.mlappinstall` on a second MATLAB R2022b (or a clean user profile) and running `tubebench sim`
  works, and a saved measurement records version and commit without `.git`.
- Scan of tree and history shows no data, CAD, credentials or unintended personal information.
- The owner's approval (§2) is recorded in this file.

## 6. Estimate and risks

- About half a day of work plus the owner's decisions in §2; history rewriting (if chosen) must
  happen before the first push and changes every commit hash already stored in saved
  measurements - say so in the CHANGELOG, or keep the history as is.
- Packaging needs MATLAB's app packaging (`matlab.apputil`), part of base MATLAB; the standalone
  route needs MATLAB Compiler installed first.
