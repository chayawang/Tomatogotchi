# Tomatogotchi

[繁體中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

A pixel pet living in a corner of your Mac desktop. Build a routine of focused work, care, and rest together. No account or AI API is required.

## Official source and safety

- Official source: [chayawang/Tomatogotchi](https://github.com/chayawang/Tomatogotchi)
- **The only official App download channel: [GitHub Releases](https://github.com/chayawang/Tomatogotchi/releases)**
- Check the publisher, filename, version, and official SHA-256. Matching names or icons do not establish provenance.
- Forks and third-party modifications are not endorsed. Source code and original assets use [BSD-3-Clause](LICENSE), which permits modification, redistribution, and commercial use subject to its conditions. Preserve the license and disclaimer; the copyright holder's or contributors' names may not be used to endorse derived products without permission.

[Official source and disclaimer](DISCLAIMER.en.md) · [Security policy](SECURITY.en.md) · [Third-party notices](THIRD_PARTY_NOTICES.en.md)

## Current version

**1.0.2 build31, public prerelease**. The download supports Apple Silicon (arm64) only. The declared minimum is macOS 13; the physical test baseline is Apple Silicon with macOS 14.4.1. Intel and the minimum OS have not been physically tested. The App has an ad-hoc development signature, **no Developer ID signature and no Apple notarization**. Downloaded installation through Finder/Gatekeeper and some native interactions still need manual verification. Automated rendering and process checks do not establish full physical-device coverage.

- Customize work and rest durations for each round, with suggested shortcuts.
- Idle, sleep, play, and short walks during work; actual walks can roam the current display's desktop and return when time expires.
- An unknown egg can hatch into a cat, dinosaur, dog, daruma, or goblin. Existing pets keep their species.
- Tombstone records preserve deceased pets' names, first meeting times, and death times after saying goodbye.

## Getting started

Read the [installation and user guide](docs/user-guide.en.md) and [release limitations](docs/releases/v1.0.2.en.md). Use `shasum -a 256 "path/to/downloaded-file"` to compare a download with the official Release's SHA256SUMS.txt. Obtain the reference from this repository; a checksum supplied by a third party does not establish the official source.

## Build from source

Requires macOS, Apple Command Line Tools (`xcode-select --install`), and Swift 5.9 or a compatible toolchain.

```sh
bash scripts/build-app.sh
```

The App is created at `build/Tomatogotchi.app`. Run the complete automated checks with:

```sh
bash scripts/verify.sh
```

Tests use separate temporary data. For manual testing, `python3 scripts/prepare-native-qa.py` creates a QA App bound to a separate data directory; open the path it prints. Do not test against your real pet data. Verification does not change system security permissions.

The repository contains no existing user or QA pet saves. Editable pixel assets are in `design/`, with generators in `scripts/make-*.py`. Fonts have a separate OFL license.
