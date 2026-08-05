# Application updates

KLM uses Sparkle 2 on macOS and WinSparkle on Windows with Ed25519 update
signatures. KLM performs one silent update probe when it opens. If a new
version exists, a persistent in-app notice lets the user start the secure
download and installation flow. It runs only while KLM is open and does not
schedule background checks.

## Distribution rules

- Release and Profile builds only run from `/Applications`.
- Debug builds may run from the build directory for local development.
- The DMG presents a fixed Finder layout with the app, an installation arrow,
  and an `Applications` link.
- The layout metadata is generated without Finder or Apple Events, so the same
  visual installer can be built in headless Codemagic workers.
- Codemagic names the distributable `klm-macOS-vX.Y.Z.dmg`; the application
  inside remains `Kontakt Library Manager.app`. Release notes state macOS
  10.15+ compatibility separately.
- The packaging script creates a temporary Python environment with hash-pinned
  `dmgbuild` dependencies; nothing is installed globally on the build machine.
- The Kontakt administrator helper remains independent from Sparkle and
  Flutter frameworks.
- Every distributed build uses the single signed legacy appcast.
- Windows is distributed as one Inno Setup executable. It installs per user in
  `%LOCALAPPDATA%\Programs\Kontakt Library Manager`, so ordinary installation
  and OTA updates do not require UAC.
- WinSparkle validates the installer with the same EdDSA key used by Sparkle on
  macOS. The native updater closes KLM before Inno Setup replaces its files.
- The Codemagic Windows workflow pins and verifies WinSparkle 0.9.4 and Inno
  Setup 7.0.2, and caches both tools between builds.

## Private key

The update private key is stored in the developer login Keychain under the
account `com.juanayala.kontaktLibraryManager`. A local exported copy may exist
at `.secrets/KLM_SPARKLE_PRIVATE_KEY`; `.secrets/` is ignored by Git.

For Codemagic, create the secret variable `KLM_SPARKLE_PRIVATE_KEY` with the
exact contents of that file. The same secret signs both platforms. Never
commit or print this value.

## Publishing an update

1. Increase the version and build number in `pubspec.yaml`.
2. Run the `macos-catalina-legacy` Codemagic workflow.
3. Publish its DMG and SHA-256 file in the matching GitHub Release.
4. Copy the generated appcast artifact to:

```text
updates/appcast-macos-legacy.xml
```

Commit the generated appcast without editing it. Existing installations will
then discover the new release through Sparkle.

## Publishing a Windows update

1. Increase the version and build number in `pubspec.yaml`.
2. Run the `windows-release` Codemagic workflow.
3. Publish the generated setup executable and SHA-256 file in the matching
   GitHub Release.
4. Copy the generated `appcast-windows.xml` artifact to:

```text
updates/appcast-windows.xml
```

Commit the appcast without editing it. Existing Windows installations will
then show the same persistent in-app update notice used on macOS. Clicking it
opens WinSparkle, which verifies, downloads, and runs the per-user installer.
