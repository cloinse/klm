# Windows installer and local GitHub release

Use this procedure from the repository root (`C:\Flutter\klm`) to validate and
package the Windows Release bundle. Add `-Publish` to upload the installer and
SHA-256 file to the matching GitHub Release and update the signed Windows
appcast on `main`.

The version and build number are read from `pubspec.yaml`. The release tag must
be `v<version>`; for example, version `0.2.9+21` uses tag `v0.2.9`.

## Prerequisites

- Flutter SDK with its Dart executable available at
  `%FLUTTER_ROOT%\bin\cache\dart-sdk\bin\dart.exe`, or at
  `%USERPROFILE%\flutter` when `FLUTTER_ROOT` is not set.
- Inno Setup 7.0.2 at `%USERPROFILE%\.klm-tools\inno-7.0.2\ISCC.exe`.
- WinSparkle 0.9.4 at `%USERPROFILE%\.klm-tools\winsparkle-0.9.4`.
- The private Ed25519 key at `.secrets\KLM_SPARKLE_PRIVATE_KEY`. This file is
  ignored by Git and must never be printed or committed.
- For publishing, create `.secrets\GITHUB_TOKEN` with the same token used by
  Codemagic, on one line without quotes. `.secrets\` is ignored by Git. The
  token needs `Contents: Read and write` permission for `cloinse/klm`.
  `GITHUB_TOKEN` remains supported for CI and temporary overrides.

## Build only

From PowerShell:

```powershell
.\tool\build_windows_release.ps1
```

The script runs Flutter analysis and tests, builds the Windows Release bundle,
copies the official WinSparkle DLL, compiles the Inno Setup installer, creates
its SHA-256 file, and generates and verifies the signed appcast using the Dart
generator.

The output directory contains exactly these three files:

```text
build/windows-release/klm-windows-v<version>/
  klm-windows-v<version>.exe
  klm-windows-v<version>.exe.sha256
  appcast-windows.xml
```

## Build and publish

Ensure the release changes are already committed and pushed to `main`, then
run:

```powershell
.\tool\build_windows_release.ps1 -Publish -Tag v<version>
```

The `-Publish` flow:

1. Creates or updates GitHub Release `v<version>`.
2. Uploads exactly the installer EXE and its `.sha256` file as Release assets.
3. Commits the generated `appcast-windows.xml` to
   `updates/appcast-windows.xml` on `main` through the GitHub Contents API.

The appcast is intentionally committed to the repository rather than uploaded
as a Release asset, matching the macOS publishing flow. The publisher replaces
existing assets with the same filenames, so rerunning a release is safe for
that release's two managed assets.

Without `-Publish`, no GitHub API call is made. If the token file is missing,
the script stops before compiling anything.
