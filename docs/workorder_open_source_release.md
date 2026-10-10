# Work order WO-002: open-source release (licence, citation, packaging, distribution)

| | |
|---|---|
| Target version | first public release (1.2.0 or later; independent of WO-001) |
| Status | planned - written 2026-10-10, decisions of the owner recorded 2026-10-10, not started |
| Requested by | the owner (Woongji Kim) |
| Purpose | make the author and the portfolio site known (<https://kimwoongji.github.io>); let other labs use the software |
| Not included | creating the GitHub repository and pushing - the owner does that (push is on hold until then) |

## 1. Decisions (owner, 2026-10-10)

- **Copyright holder:** Woongji Kim.
- **E-mail in the git history:** may be public (`wj.kim@postech.ac.kr`); the history is published
  as it is, no rewriting.
- **Lab configuration:** `config/user_config.json` (lab instrument addresses, microphones,
  geometry) may be public and stays in the repository as the lab's working example.
- **Distribution:** GitHub repository `kimwoongji/tubebench`, linked to MATLAB File Exchange (the
  File Exchange entry follows the GitHub releases).
- **Licence: MIT** (recommended 2026-10-10 for the purpose above - confirm when starting):
  - the most widely known and shortest permissive licence on GitHub and File Exchange, so the
    lowest barrier for others to use, fork and mention the project - more use means more
    visibility of the author;
  - every copy and substantial portion must keep the line `Copyright (c) 2026 Woongji Kim`, so
    the author's name travels with the code;
  - a licence cannot force a visible credit in someone else's program; visibility comes from
    the README, CITATION.cff (GitHub's "Cite this repository" button), the File Exchange page,
    and the credit already shown in the program (start window and Help > About:
    kimwoongji.github.io).
  - Alternative if redistributors should carry a credit file: Apache-2.0 with a `NOTICE` file
    ("tubebench by Woongji Kim - https://kimwoongji.github.io"); Apache-2.0 requires
    redistributions to include that NOTICE text, at the cost of a longer licence. BSD-3-Clause
    adds nothing for promotion (its third clause only restricts the use of the author's name).
    Copyleft (GPL) would reduce adoption and is awkward for code on proprietary MATLAB.

## 2. Current state (checked 2026-10-10)

- Required products (`matlab.codetools.requiredFilesAndProducts`): **MATLAB R2022b and Signal
  Processing Toolbox** only. Instrument communication uses base MATLAB (TCP, HTTP).
- Never committed: `data/`, `calibration/`, `cad/` (checked over the whole history). Largest
  tracked file 0.25 MB (`tests/fixtures`, recorded from the lab's own LAN-XI module).
- Third-party material: the HBK `open-api-time-data-recorder` (MIT) and `open-api-tutorials`
  (Kaitai format description, no licence file) are behavioural/format references only, no code
  copied (docs/ref_lanxi_openapi.md). No manuals or datasheets are in the repository.
- Credits in the program: start window (kimwoongji.github.io, link), Help > About (link),
  Help > Source code on GitHub.
- Version and commit are written into every measurement (`tim.app.softwareVersion`); the commit
  comes from git and is unknown in an installed package without `.git`.
- No LICENSE, CITATION.cff or CHANGELOG yet. README says the repository is not created yet.

## 3. Tasks

1. **LICENSE** (MIT, `Copyright (c) 2026 Woongji Kim`); a "License" section in README; the
   copyright/licence line in the help header of the entry files only (`tubebench.m`,
   `+tim/+gui/TubeApp.m`).
2. **Author visibility:**
   - README header: name, logo (`resources/logo`), one-line description, links to
     <https://kimwoongji.github.io> and the File Exchange page, badges (licence, MATLAB version,
     File Exchange, DOI after step 3).
   - Screenshots and a short GIF of a simulated calibration and measurement in README
     (from `examples/output` or new captures).
   - GitHub repository description, topics (matlab, acoustics, impedance-tube, transmission-loss,
     transfer-impedance, lan-xi), social preview image (logo + name).
   - Suggest to the owner: a project page on kimwoongji.github.io that links back to the
     repository and the File Exchange page.
3. **CITATION.cff** (title tubebench, author Woongji Kim with ORCID if available, version, date,
   licence, repository URL, a preferred-citation entry if a paper follows); a "How to cite"
   section in README; after the first GitHub release, connect the repository to Zenodo for a DOI
   per release and add the DOI badge.
4. **CHANGELOG.md** from the git history (grouped per version: 1.0 bench tests, 1.1 GUI and
   analysis review, 1.2 …); release notes per tag.
5. **Release script `tools/make_release.m`:** (a) check the working tree is clean and the tests
   pass; (b) write the commit hash and date into a build-info file that `softwareVersion` uses
   when `.git` is absent; (c) build a **toolbox package `tubebench.mltbx`** (installable from
   MATLAB's Add-On Explorer; app entry `tubebench`, icon from `resources/logo`; check whether File
   Exchange uses a `.mltbx` attached to the GitHub release, otherwise the release zip); (d) zip
   the source; (e) print checksums. The installed toolbox must start the same way (`tubebench`,
   `tubebench sim`) and keep config, data and calibrations in a writable user folder when the
   installation folder is read-only (decide the folder: Documents\tubebench or similar).
6. **Public README:** what it measures, requirements (MATLAB R2022b+, Signal Processing Toolbox;
   hardware: 33220A + LAN-XI 3676 until WO-001 adds drivers), install (File Exchange / Add-On
   Explorer, clone, zip), "try it without hardware" (`tubebench sim`), validation status
   (software-verified vs. hardware-verified, docs/hardware_status.md), licence, citation, author.
7. **CONTRIBUTING.md** (issues welcome, tests must pass with `run_tests`, code style of the
   repository, no raw data in commits) and a short **safety note** (the program drives a
   loudspeaker: level limits, output-off rules).
8. **Repository hygiene:** `.gitattributes` (`*.bat` CRLF, others LF); check `.gitignore`;
   ONBOARDING.md stays untracked (or becomes part of CONTRIBUTING); a final scan of tree and
   history for credentials and local paths with user names (e.g. `C:\Users\Rholab` in docs).
9. **File Exchange:** after the first GitHub release, create the File Exchange entry linked to
   the repository (title, summary, product requirements, tags, screenshot, author profile link
   to kimwoongji.github.io).
10. **Optional later:** standalone application (assumptions_and_limitations.md item 9; MATLAB
    Compiler is licensed but not installed); "Open in MATLAB Online" badge.

## 4. Acceptance

- LICENSE (MIT, Woongji Kim), CITATION.cff, CHANGELOG.md present; README with author, links,
  screenshots, install and licence sections; all tests pass.
- `tools/make_release.m` produces `tubebench.mltbx` and the source zip from a clean tree;
  installing the toolbox in a second MATLAB R2022b (or a clean user profile) and running
  `tubebench sim` works, and a saved measurement records version and commit without `.git`.
- Scan of tree and history: no data, CAD or credentials.
- The owner creates the GitHub repository, pushes, makes the first release and links File
  Exchange; the work order then records the release tag, the File Exchange URL and the DOI.

## 5. Estimate and risks

- About half a day of work. The repository URL in the code (`tim.app.repositoryUrl`) already
  points to `github.com/kimwoongji/tubebench`.
- File Exchange's handling of GitHub releases (zip vs. attached `.mltbx`) should be checked on
  MathWorks' current documentation when doing step 5/9.
- Measurement folders saved before the release keep their old program name and local paths in
  their metadata (information only; raw data are never modified).
