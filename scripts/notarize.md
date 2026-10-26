# Signing and notarizing releases

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed (`git tag v0.2.0 && git push origin
v0.2.0`). It runs `scripts/package.sh <version>`, which builds the app, signs the embedded `asb` and then the app
with the hardened runtime, notarizes and staples, and writes `dist/agentic-status-bar-<version>.zip` (only the `.app`)
and `dist/agentic-status-bar-<version>.dmg`. The workflow attaches both to a **draft** GitHub release; publish it by
hand.

`scripts/package.sh 0.0.0` without `IDENTITY` makes an ad-hoc signed dry run locally (no notarization).

## One-time setup

0. **Join the Apple Developer Program.** A free Apple Account can't create Developer ID certificates; the paid
   membership (99 USD a year) can. Sign in at developer.apple.com › **Account** and use its **Enroll** button (or the
   [enrollment page](https://developer.apple.com/programs/enroll/), or the **Apple Developer** app on a Mac, iPhone
   or iPad, which Apple suggests for individuals; finish on the same device you start on). You need:
   - an Apple Account with two-factor authentication;
   - as an **individual**, your legal name (no alias or company name, which delays the review) and a photo ID;
   - as an **organization**, a legal entity, a D-U-N-S Number, a work email and website on its domain, and the
     authority to sign for it.

   Apple reviews the request and emails you; then you agree to the license and pay. The membership shows in the
   Account page once active (Apple says to contact Developer Support if it hasn't within 24 hours of paying). Whoever
   enrolls is the **Account Holder**, the role the next step needs.
1. **Developer ID Application certificate.** Creating one needs the Account Holder role. On the developer website
   (these steps don't depend on the Xcode version):
   1. Make a certificate signing request: open **Keychain Access** (Spotlight finds it), choose **Keychain Access ›
      Certificate Assistant › Request a Certificate from a Certificate Authority**, enter your email address and a
      common name, leave the CA email address empty, choose **Saved to disk** and save the `.certSigningRequest` file
      anywhere outside the repository. It is only needed for the upload below; making it also puts the private key
      in your login keychain, so do this whole step on the Mac you'll export from.
   2. At developer.apple.com › Account › **Certificates, Identifiers & Profiles** › **Certificates**, click **+**,
      choose **Developer ID**, then **Developer ID Application**, and continue. If asked for an intermediary, choose
      **G2 Sub-CA**. Upload the request file and download the `.cer` file.
   3. Double-click the `.cer` file: it appears in Keychain Access under **My Certificates** as "Developer ID
      Application: <your name> (<team ID>)", with its private key.
   4. Export it: select it in **My Certificates**, choose **File › Export Items…**, pick **Personal Information
      Exchange (.p12)**, and set a password.

   Xcode can also create the certificate from its account settings (Manage Certificates); the menu names differ
   between Xcode versions, so the website route is the one described here.
2. **App Store Connect API key** for `notarytool`. At appstoreconnect.apple.com › Users and Access › Integrations ›
   App Store Connect API, create a team key with the **Developer** role. Download the `AuthKey_<KEYID>.p8` file (it
   can be downloaded only once) and note the **Key ID** and the **Issuer ID** shown on that page.
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
