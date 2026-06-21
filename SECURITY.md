# Security notes

Frontend security measures implemented in this app, plus build-time steps that
require action on your side (they need secrets/keys that must not be committed).

## Implemented in code

- **Safe markdown links** — links in AI responses are scheme-allowlisted
  (`http`/`https`/`mailto` only) and require a confirmation dialog showing the
  real destination before opening. See `lib/core/security/safe_link.dart`.
- **Transport** — the backend URL is supplied at build time via
  `--dart-define=API_BASE_URL=...` (no production URL hardcoded). Release builds
  refuse a non-HTTPS URL. Android cleartext HTTP is allowed in **debug only**
  (`android/app/src/debug/AndroidManifest.xml`); release builds block it. iOS
  ATS blocks cleartext by default.
- **Input / attachment validation** — outgoing messages are capped at
  `kMaxMessageLength` (8000) chars; attachments are validated by their bytes
  (PDF magic header, UTF-8 for text, decode-or-reject for images) to defeat
  extension spoofing. See `lib/core/security/attachment_validator.dart`.
- **Screen privacy** — Android `FLAG_SECURE` (blocks screenshots and blanks the
  app-switcher preview) is a user setting, default ON, persisted across launches.
  See `lib/core/security/screen_security.dart` and the settings sheet.
- **Manifest hardening** — `android:allowBackup="false"`, unused Bluetooth
  permissions removed, web Content-Security-Policy added in `web/index.html`.
- **Error hygiene** — user-facing errors no longer leak the backend URL
  (full detail only in debug builds).

## Build-time steps (require your action)

### Run against an HTTPS backend
```
flutter build apk --release --dart-define=API_BASE_URL=https://your-api.example.com
```
A release build without an HTTPS `API_BASE_URL` will throw on startup by design.

### Release signing (don't ship debug keys)
`android/app/build.gradle.kts` currently signs release with the debug keystore.
Generate a real keystore and wire a `signingConfig`:
```
keytool -genkey -v -keystore ~/zenith-release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias zenith
```
Store the path/passwords in `android/key.properties` (gitignored — never commit
it) and reference it from a `signingConfigs { create("release") { ... } }` block,
then set `release { signingConfig = signingConfigs.getByName("release") }`.

### Obfuscate release builds
```
flutter build apk --release --obfuscate --split-debug-info=build/symbols \
  --dart-define=API_BASE_URL=https://your-api.example.com
```
Keep the `build/symbols` directory to de-obfuscate crash stack traces.

## Out of scope (needs backend)

Request authentication/authorization, server TLS termination, and server-side
input validation / rate limiting are backend concerns and are not addressed here.
The frontend is ready to send an `Authorization` header once a backend auth
scheme exists.
