# Original PowerPointLabs source provenance

- **Original developers:** PowerPointLabs contributors, National University of Singapore
- **Original repository:** https://github.com/PowerPointLabs/PowerPointLabs
- **Original license:** GNU General Public License, version 2 (GPLv2)
- **Source revision chosen:** `79e6be4882b736a0cb4828e06a96286de9b3aed6`
- **Commit:** https://github.com/PowerPointLabs/PowerPointLabs/commit/79e6be4882b736a0cb4828e06a96286de9b3aed6
- **Commit date:** 2020-05-16
- **Git submodule path:** `upstream/PowerPointLabs`
- **Version evidence:** `PowerPointLabs/PowerPointLabs/PowerPointLabs.csproj` at the above revision declares `<ApplicationVersion>6.1.0.2</ApplicationVersion>`.

The `upstream/PowerPointLabs` gitlink and `.gitmodules` pin the upstream repository to this specific immutable Git commit, rather than its moving `master` branch. This preserves a reproducible reference to the original source and keeps it separate from our installer and certificate work. A submodule **references** the upstream Git source; it does not copy its objects into this repository. Users must fetch the submodule to obtain those files.

## Retrieve pinned source

```bat
git clone --recurse-submodules https://github.com/FredThompsonII/PowerPointLabsLives.git
cd PowerPointLabsLives
git -C upstream/PowerPointLabs rev-parse HEAD
```

The final command must print `79e6be4882b736a0cb4828e06a96286de9b3aed6`.

If the top-level repository is already cloned:

```bat
git submodule update --init --recursive
```

**Scope:** This identifies the upstream revision selected for inclusion. No source-to-binary identity assertion is made, and the pinned source has not been rebuilt or modified as part of this source-provenance step.
