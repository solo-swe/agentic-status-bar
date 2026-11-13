---
name: check-release
description: Check a release of Agentic Status Bar (doc/RELEASING.md › Checking a release) and report a table of results. Use when the user says "check the release", "check the draft", "check v0.3.1", or at the checking steps of a release task.
argument-hint: <version, e.g. 0.3.1> [published]
allowed-tools:
  - Bash(mkdir -p .build/release-check/*)
  - Bash(gh release download v* --dir .build/release-check/*)
  - Bash(gh release view v*)
  - Bash(ditto -x -k .build/release-check/*)
  - Bash(spctl --assess *)
  - Bash(codesign --verify *)
  - Bash(xcrun stapler validate *)
  - Bash(plutil -p *)
  - Bash(gh variable get SPARKLE_PUBLIC_KEY)
  - Bash(curl -fsSIL https://github.com/solo-swe/agentic-status-bar/releases/*)
  - Bash(gh run list --workflow homebrew.yml *)
  - Bash(ls *)
  - Read
---

# Check a release

Runs the checks of `doc/RELEASING.md` › Checking a release for one version and reports them as a table. The
commands above run without a prompt; the user approved exactly this list (T-150). Don't run anything else here
without asking, and never change the release: publishing, editing notes and deleting tags are the user's.

The arguments are the version without the `v` (`0.3.1`), and `published` once the user has published it. Below,
`V` is the version and `D` is `.build/release-check/V` (ignored by git). Run each command on its own, as written,
with no pipes or chains.

## The draft

1. `mkdir -p D`, then `gh release download vV --dir D` (it lists `agentic-status-bar-V.zip`, `.dmg` and
   `appcast.xml`; a missing one is a failed check). If `D` already holds the files from an earlier run, use them.
2. `ditto -x -k D/agentic-status-bar-V.zip D/unzipped`. Below, `APP` is `D/unzipped/Agentic Status Bar.app`.
3. Gatekeeper:
   - `spctl --assess --type open --context context:primary-signature --verbose D/agentic-status-bar-V.dmg`: accepted.
   - `spctl --assess --type execute --verbose "APP"`: accepted, `source=Notarized Developer ID`.
4. `codesign --verify --deep --strict --verbose=2 "APP"`: valid on disk, satisfies its Designated Requirement.
5. `xcrun stapler validate D/agentic-status-bar-V.dmg`: the validate action worked.
6. `plutil -p "APP/Contents/Info.plist"`:
   - `CFBundleShortVersionString` is `V`; `CFBundleVersion` is a number above the previous release's (say which);
   - `SUFeedURL` is `https://github.com/solo-swe/agentic-status-bar/releases/latest/download/appcast.xml`;
   - `SUPublicEDKey` equals the output of `gh variable get SPARKLE_PUBLIC_KEY`.
7. Read `D/appcast.xml`: `sparkle:shortVersionString` is `V`, `sparkle:version` equals `CFBundleVersion`, the
   enclosure URL ends in `/releases/download/vV/agentic-status-bar-V.zip`, and its `length` equals the zip's size
   (`ls -l D/agentic-status-bar-V.zip`).
8. `gh release view vV`: still a draft, with the three assets.

## Once published (`published`)

1. `curl -fsSIL https://github.com/solo-swe/agentic-status-bar/releases/latest/download/appcast.xml`: the last status
   is 200.
2. `curl -fsSIL https://github.com/solo-swe/agentic-status-bar/releases/download/vV/agentic-status-bar-V.zip`: 200.
3. `gh run list --workflow homebrew.yml --limit 1`: a successful run for `vV`.

## Report

One table: check, result (✅ or ❌), and what was seen when it failed or when the value matters (the build number, the
key's first characters). Then the checks left to the user, which need their keychain or change their machine:

- the appcast's signature, on the Mac that holds the Sparkle key:
  `.build/release-xcode/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --verify D/agentic-status-bar-V.zip "<sparkle:edSignature from D/appcast.xml>"`
  (fill in the signature for them);
- once published: `brew update`, then `brew info --cask solo-swe/tap/agentic-status-bar` shows `V`;
- once published: an installed copy of the previous version offers the update under **Check for Updates…**.

A failed check: say what `doc/RELEASING.md` › When something fails suggests, and stop there; fixing it is a decision
for the user.
