# Releasing

How a release is built, signed, published and delivered, the one-time setup it needs, and what to do when a step
fails. Everything here runs from a tag; nothing is built on a laptop for a release.

## How a release flows

```
git tag v0.3.0 ─push─▶ .github/workflows/release.yml (macOS runner)
                         │ imports the Developer ID certificate, writes the notary and Sparkle keys
                         ▼
                       scripts/package.sh 0.3.0
                         │ checks: the tag matches ASBVersion.current; the Sparkle key pair matches
                         │ builds the app (XcodeGen + xcodebuild), writes SUPublicEDKey into it
                         │ signs inside out: Sparkle's helpers, Sparkle.framework, asb, the app
                         │ notarizes the zip, staples the app, zips again; builds, signs, notarizes, staples the DMG
                         ▼
                       scripts/appcast.sh ─▶ appcast.xml (the zip, signed with the Sparkle key)
                         ▼
                       draft GitHub release: agentic-status-bar-0.3.0.zip, .dmg, appcast.xml
                         │
               you publish it, as the latest release (not a pre-release)
                         │
          ┌──────────────┴──────────────────────────────┐
          ▼                                              ▼
installed apps (Sparkle) read                    .github/workflows/homebrew.yml (on release: published)
releases/latest/download/appcast.xml,            computes the zip's sha256 (scripts/homebrew-cask.sh) and
download the zip, check its signature,           pushes Casks/agentic-status-bar.rb to solo-swe/homebrew-tap
install it                                       with the deploy key
```

Two things follow from this:

- **Publishing is what ships.** A draft reaches nobody. The app's feed (`SUFeedURL` in `App/project.yml`) is
  `releases/latest/download/appcast.xml`, and GitHub's "latest" skips drafts and pre-releases.
- **One version for everything:** `ASBVersion.current` in `Sources/ASBCore/Version.swift` is the version of `asb`,
  the app and the tag. `MARKETING_VERSION` in `App/project.yml` repeats it for builds made in Xcode. The build number
  (`CFBundleVersion`, what Sparkle compares) is the release workflow's run number, so it only grows.

## One-time setup

Done once per project; the result is the secrets and the variable below. Apple renames buttons now and then: each step
links the help page with the current wording.

### 1. Apple Developer Program

[Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment). Developer ID
certificates need the paid membership (99 USD a year, shown in local currency). Start from developer.apple.com/account,
the [enrollment page](https://developer.apple.com/programs/enroll/), or the **Apple Developer** app. You need an Apple
Account with two-factor authentication; an individual enrolls under their legal name, an organization needs a D-U-N-S
Number. Apple emails an order acknowledgement, then a confirmation once the order is processed (it can take up to 48
hours). Whoever enrolls is the **Account Holder**, the role the next two steps need.

### 2. Developer ID Application certificate

[Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
Only the Account Holder can create one; a team can have up to five.

1. Make a certificate signing request
   ([how](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)): **Keychain
   Access › Certificate Assistant › Request a Certificate from a Certificate Authority**, your email in **User Email
   Address**, a name in **Common Name**, **CA Email Address** empty, **Saved to disk**. Save the `.certSigningRequest`
   outside the repository; it's only needed for the upload. Making it puts the private key in your login keychain, so
   do the whole step on one Mac.
2. In **Certificates, Identifiers & Profiles › Certificates**, click **+**, then under **Software** choose **Developer
   ID** › **Developer ID Application**. Not **Apple Development** or **Apple Distribution**: Gatekeeper doesn't accept
   those for an app downloaded from the web. **Developer ID Installer** is for `.pkg` installers, not needed here.
3. Upload the request (**Choose File**, **Continue**), then **Download** the `.cer`.
4. Double-click the `.cer`: it appears in Keychain Access under **My Certificates** as "Developer ID Application: <your
   name> (<team ID>)", with its private key under it.
5. Select it, **File › Export Items…**, **Personal Information Exchange (.p12)**, and set a password.

### 3. App Store Connect API key, for notarization

[App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api), at
appstoreconnect.apple.com:

1. **Users and Access › Integrations**. The first time, the Account Holder clicks **Request Access**, agrees and
   submits; Apple reviews it, so it may take a while.
2. **Team Keys › Generate API Key** (or **+**), a name, **Developer** under **Access**, **Generate**. A team key, not an
   individual one: the workflow needs the team's Issuer ID.
3. Download `AuthKey_<KEYID>.p8` (only possible once) and note the **Key ID** and the **Issuer ID** shown above the
   list.

### 4. Sparkle update key

An EdDSA key pair: the private key signs each update, the public key is built into the app, which installs only
updates signed with it. Build the app once so Sparkle's tools are downloaded (`scripts/package.sh 0.0.0`), then:

```sh
bin=.build/release-xcode/SourcePackages/artifacts/sparkle/Sparkle/bin
$bin/generate_keys                     # creates the key pair in your login keychain
$bin/generate_keys -x sparkle.key
gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle.key
gh variable set SPARKLE_PUBLIC_KEY --body "$($bin/generate_keys -p)"
rm sparkle.key
```

Set the variable from `generate_keys -p`, which prints only the key. The first command prints it inside an Info.plist
snippet, and copying from there tends to bring a stray `<` along (see When something fails).

**Back up the private key:** it lives in your login keychain; keep a copy of an export (`generate_keys -x`) somewhere
safe, such as a password manager, before deleting the file. See Replacing keys for why.

### 5. Homebrew tap

[solo-swe/homebrew-tap](https://github.com/solo-swe/homebrew-tap) is a public repository holding
`Casks/agentic-status-bar.rb`. The Homebrew workflow pushes to it with a deploy key: write access to that one
repository and nothing else.

1. The organization must allow deploy keys: the **Deploy keys** setting in the solo-swe organization's settings
   (GitHub refuses the key with "Deploy keys are disabled for this repository" otherwise).
2. Make a key pair and install it:

   ```sh
   ssh-keygen -t ed25519 -N "" -C "agentic-status-bar release → homebrew-tap" -f tap-key
   gh repo deploy-key add tap-key.pub --repo solo-swe/homebrew-tap --allow-write --title "agentic-status-bar release workflow"
   gh secret set HOMEBREW_TAP_DEPLOY_KEY --repo solo-swe/agentic-status-bar < tap-key
   rm tap-key tap-key.pub
   ```

   The key needs no backup: a lost one is replaced by running these again.

### Secrets and variables

All in solo-swe/agentic-status-bar › Settings › Secrets and variables › Actions (`gh secret list`, `gh variable list`).

| Name | Kind | What it is | Comes from | To replace it |
| --- | --- | --- | --- | --- |
| `DEVELOPER_ID_CERT_P12` | secret | The certificate and its private key, base64 | step 2: `base64 -i cert.p12 \| gh secret set DEVELOPER_ID_CERT_P12` | export again, or make a new certificate (step 2) |
| `DEVELOPER_ID_CERT_PASSWORD` | secret | The `.p12` password | step 2 | set with the new `.p12` |
| `NOTARY_API_KEY_P8` | secret | The API key, base64 | step 3: `base64 -i AuthKey_KEYID.p8 \| gh secret set NOTARY_API_KEY_P8` | revoke it and generate a new one (step 3), then set all three notary values |
| `NOTARY_API_KEY_ID` | secret | The Key ID | step 3 | with a new key |
| `NOTARY_API_ISSUER_ID` | secret | The team's Issuer ID | step 3 | doesn't change |
| `SPARKLE_ED_PRIVATE_KEY` | secret | The private update key, as `generate_keys -x` exports it | step 4 | from the keychain backup; a new pair has consequences (Replacing keys) |
| `SPARKLE_PUBLIC_KEY` | variable | The public update key, built into release builds | step 4: `generate_keys -p` | always together with the private key |
| `HOMEBREW_TAP_DEPLOY_KEY` | secret | The private half of the tap's deploy key | step 5 | make a new pair (step 5) and remove the old deploy key from the tap |

Once the secrets are set, delete the exported `.p12` and `.p8` from your disk and keep backups somewhere safe.

## Each release

1. Set the version: `ASBVersion.current` in `Sources/ASBCore/Version.swift` and `MARKETING_VERSION` in
   `App/project.yml`, and the version in the README's build-it-yourself example.
2. Run the checks (`swift test`, `tests/app.sh --test`, `tests/lint.sh`), commit, push, and wait for CI.
3. Tag and push the tag: `git tag -a v0.3.0 -m v0.3.0 && git push origin v0.3.0`.
4. Watch the release run (`gh run list --workflow release.yml`, `gh run watch <id>`). It drafts the release.
5. Check the draft (Checking a release, below) and edit its notes; they're generated from the commits.
6. Publish it with **Set as the latest release** on and **Set as a pre-release** off.
7. Check the published release: the downloads work without a GitHub login, and the Homebrew workflow ran and the tap
   has the new version.

A dry run on your Mac: `scripts/package.sh 0.0.0` builds and signs ad hoc, skips notarization, and makes no appcast.
Such builds don't update themselves (they have no public key).

## Checking a release

On the draft, after `gh release download v0.3.0 --dir <empty folder>` and `ditto -x -k
agentic-status-bar-0.3.0.zip unzipped`:

```sh
spctl --assess --type open --context context:primary-signature --verbose agentic-status-bar-0.3.0.dmg
spctl --assess --type execute --verbose "unzipped/Agentic Status Bar.app"   # accepted, source=Notarized Developer ID
codesign --verify --deep --strict --verbose=2 "unzipped/Agentic Status Bar.app"
xcrun stapler validate agentic-status-bar-0.3.0.dmg
plutil -p "unzipped/Agentic Status Bar.app/Contents/Info.plist"   # version, SUFeedURL, SUPublicEDKey
```

`SUFeedURL` must be `https://github.com/solo-swe/agentic-status-bar/releases/latest/download/appcast.xml` and
`SUPublicEDKey` the same as `gh variable get SPARKLE_PUBLIC_KEY`. `appcast.xml` must name this version, point at this
release's zip, and carry the zip's size. On the Mac that holds the key, check its signature:

```sh
$bin/sign_update --verify agentic-status-bar-0.3.0.zip "<sparkle:edSignature from appcast.xml>"
```

After publishing:

```sh
curl -fsSIL https://github.com/solo-swe/agentic-status-bar/releases/latest/download/appcast.xml   # ends in 200
curl -fsSIL https://github.com/solo-swe/agentic-status-bar/releases/download/v0.3.0/agentic-status-bar-0.3.0.zip
gh run list --workflow homebrew.yml --limit 1
brew update && brew info --cask solo-swe/tap/agentic-status-bar   # shows the new version
```

An installed copy of the previous version offers the update under **Check for Updates…**.

## When something fails

| What you see | Why | What to do |
| --- | --- | --- |
| `The Sparkle private key doesn't match SPARKLE_PUBLIC_KEY` (package step) | The two halves don't belong together; most often a stray `<` at the end of the variable, copied from `generate_keys`' Info.plist snippet | `gh variable get SPARKLE_PUBLIC_KEY` and compare with `generate_keys -p`; set it again from `generate_keys -p`, and re-run the failed job (`gh run rerun <id> --failed`) |
| `A signed release needs SPARKLE_PUBLIC_KEY and SPARKLE_KEY_FILE` | The variable or the `SPARKLE_ED_PRIVATE_KEY` secret is missing (a repository transfer doesn't carry variables) | Set them (One-time setup, step 4) |
| `Version 0.3.0 doesn't match ASBVersion.current` | The tag and `Sources/ASBCore/Version.swift` differ | Delete the tag (`git push origin :v0.3.0`, `git tag -d v0.3.0`), fix the version, tag again |
| Notarization fails or hangs | Apple refused the build, or the API key is wrong | The run log has the submission ID: `xcrun notarytool log <id> --key <p8> --key-id <id> --issuer <issuer>` says why. A wrong key: check the three notary secrets |
| Certificate import or `codesign` fails | The `.p12` or its password is wrong, or the certificate expired | Export again and set both secrets |
| Apps don't see the update | The release is a draft or a pre-release, or another release is marked latest | Edit the release: published, not a pre-release, latest |
| The Homebrew workflow fails at `git clone` | The deploy key is missing, read-only, or the organization disallows deploy keys | `gh repo deploy-key list --repo solo-swe/homebrew-tap`; redo step 5 |
| The tap wasn't updated | The workflow skips pre-releases, or didn't run | Run it by hand: `gh workflow run homebrew.yml -f tag=v0.3.0` |
| `brew` refuses the cask from an untrusted tap | Homebrew 6 requires trusting third-party taps | `brew install --cask solo-swe/tap/agentic-status-bar` trusts it; for other commands `brew trust --cask solo-swe/tap/agentic-status-bar` |

## Replacing keys

- **The Sparkle key pair.** Installed copies trust only the public key they were built with. A release signed with a
  new key is refused by every copy out there: their users would have to download the new version by hand, once. So
  back up the private key, and replace the pair only if it leaked.
- **The Developer ID certificate.** It expires after five years; make a new one (step 2) and set the two
  certificate secrets. Installed copies update fine: Sparkle checks the EdDSA signature, and the new certificate
  belongs to the same team. A different team (another Apple account, or moving from an individual to an
  organization membership) is a bigger change: macOS ties some permissions, such as notifications, to the team, so
  users may be asked again.
- **The notarization key.** Revoke it in App Store Connect and generate a new one; nothing installed is affected.
- **The tap's deploy key.** Make a new pair, update the secret and remove the old key from the tap; nothing installed
  is affected.
