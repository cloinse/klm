# Application updates

KLM uses Sparkle 2 on macOS with ad-hoc application signatures and Ed25519
update signatures. The updater is manual and runs only while KLM is open.

## Distribution rules

- Release and Profile builds only run from `/Applications`.
- Debug builds may run from the build directory for local development.
- The DMG presents a fixed Finder layout with the app, an installation arrow,
  and an `Applications` link.
- The Kontakt administrator helper remains independent from Sparkle and
  Flutter frameworks.
- The current and Catalina builds use separate signed appcasts.

## Private key

The update private key is stored in the developer login Keychain under the
account `com.juanayala.kontaktLibraryManager`. A local exported copy may exist
at `.secrets/KLM_SPARKLE_PRIVATE_KEY`; `.secrets/` is ignored by Git.

For Codemagic, create the secret variable `KLM_SPARKLE_PRIVATE_KEY` with the
exact contents of that file. Never commit or print this value.

## Creating a local DMG and appcast

```bash
flutter build macos --release
tool/package_macos_dmg.sh \
  "build/macos/Build/Products/Release/Kontakt Library Manager.app" \
  "build/distribution/Kontakt-Library-Manager-macOS-12-v1.1.0.dmg"

KLM_UPDATE_DOWNLOAD_URL_PREFIX="https://github.com/cloinse/klm/releases/download/v1.1.0" \
  tool/generate_macos_appcast.sh \
  build/distribution \
  updates/appcast-macos-current.xml
```

Publish the DMG and its checksum in the matching GitHub release, then commit
the generated signed appcast. The first OTA-capable release must be installed
manually; later releases can replace it through Sparkle.
