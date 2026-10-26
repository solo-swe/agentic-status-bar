# Signing and notarizing releases

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed (`git tag v0.2.0 && git push origin
v0.2.0`). It runs `scripts/package.sh <version>`, which builds the app, signs the embedded `asb` and then the app
with the hardened runtime, notarizes and staples, and writes `dist/agentic-status-bar-<version>.zip` (only the `.app`)
and `dist/agentic-status-bar-<version>.dmg`. The workflow attaches both to a **draft** GitHub release; publish it by
hand.

`scripts/package.sh 0.0.0` without `IDENTITY` makes an ad-hoc signed dry run locally (no notarization).

## One-time setup

These steps follow Apple's Account Help and App Store Connect Help (links at each step); Apple renames buttons now and
then, so if one differs, the linked page has the current wording.

0. **Join the Apple Developer Program**
   ([Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)). Developer ID
   certificates need the paid membership (99 USD a year, shown in local currency). Start from your account at
   developer.apple.com/account, the [enrollment page](https://developer.apple.com/programs/enroll/), or the
   **Apple Developer** app. You need an Apple Account with two-factor authentication; an individual enrolls under
   their legal name (an alias or company name delays it), an organization needs a D-U-N-S Number. Individuals agree
   to the license and pay during enrollment; organizations pay after Apple verifies them. Apple first emails an
   order acknowledgement, then a confirmation once the order is processed; the membership then shows in your account.
   Whoever enrolls becomes the **Account Holder**, the role steps 1 and 2 need.
1. **Developer ID Application certificate**
   ([Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)).
   Only the Account Holder can create it; a team can have up to five.
   1. Make a certificate signing request
      ([how](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request)): open
      **Keychain Access** (in `/Applications/Utilities`), choose **Keychain Access › Certificate Assistant › Request
      a Certificate from a Certificate Authority**, enter your email address in **User Email Address** and a name for
      the key in **Common Name**, leave **CA Email Address** empty, select **Saved to disk** and click **Continue**.
      Save the `.certSigningRequest` file anywhere outside the repository: it is only needed for the upload below
      and can be deleted after. Making it also puts the private key in your login keychain, so do this whole step
      on the Mac you'll export from.
   2. In your account, open **Certificates, Identifiers & Profiles**, click **Certificates** in the sidebar, then the
      add button (**+**).
   3. Under **Software**, select **Developer ID** and click **Continue**, then choose **Developer ID Application**
      (it signs a Mac app; **Developer ID Installer** is for `.pkg` installers, not needed here). Not **Apple
      Development** or **Apple Distribution**: those sign development builds and App Store or Ad Hoc builds, which
      Gatekeeper doesn't accept for an app downloaded from the web.
   4. Click **Choose File**, select the `.certSigningRequest` file, click **Continue**, then **Download**. The `.cer`
      file goes to `Downloads`.
   5. Double-click the `.cer` file: it appears in Keychain Access under **My Certificates** as "Developer ID
      Application: <your name> (<team ID>)", with the private key under it.
   6. Export it: select it in **My Certificates**, choose **File › Export Items…**, pick **Personal Information
      Exchange (.p12)**, and set a password.
2. **App Store Connect API key** for `notarytool`
   ([App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)).
   At appstoreconnect.apple.com:
   1. **Users and Access › Integrations** opens with **App Store Connect API** selected. The first time, the Account
      Holder clicks **Request Access**, agrees to the terms and clicks **Submit**; Apple reviews the request, so it
      may not be approved at once.
   2. Click **Team Keys**, then **Generate API Key** (or **+** if there's a key already). Enter a name, choose
      **Developer** under **Access**, and click **Generate**. Make a team key, not an individual key (Edit Profile ›
      Individual API Key): the secrets below use the team's Issuer ID.
   3. Download the `AuthKey_<KEYID>.p8` file (it can be downloaded only once) and note the **Key ID** shown for the
      key and the **Issuer ID** shown above the list.
3. **Repository secrets.** Add these in GitHub › Settings › Secrets and variables › Actions, or with `gh secret set`:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | the `.p12` file, base64: `base64 -i cert.p12 \| gh secret set DEVELOPER_ID_CERT_P12` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` password |
| `NOTARY_API_KEY_P8` | the `.p8` file, base64: `base64 -i AuthKey_KEYID.p8 \| gh secret set NOTARY_API_KEY_P8` |
| `NOTARY_API_KEY_ID` | the Key ID |
| `NOTARY_API_ISSUER_ID` | the Issuer ID |

Delete the exported `.p12` and the `.p8` from your disk once the secrets are set (keep a backup somewhere safe).

## Checking a release

After downloading the DMG or zip on another Mac:

```sh
spctl --assess --type execute --verbose "/Applications/Agentic Status Bar.app"   # accepted, source=Notarized Developer ID
codesign --verify --deep --strict --verbose=2 "/Applications/Agentic Status Bar.app"
xcrun stapler validate agentic-status-bar-<version>.dmg
```
