# macOS build matrix

The application uses the same one-shot administrator helper in both deployment
families. It is bundled as an executable resource and is never installed as a
daemon or registered as a background/Login Item service.

| Variant | Deployment target | Authorization mechanism | Build environment |
| --- | --- | --- | --- |
| Current | macOS 12+ | One-shot bundled helper and the standard macOS administrator dialog | Current local Flutter/Xcode |
| Catalina | macOS 10.15+ | The same one-shot bundled helper | Codemagic: Flutter 3.38.9 (Dart 3.10.8), Xcode 16.4 |

The checked-in Xcode project intentionally remains on macOS 12. The
`macos-catalina-legacy` workflow in `codemagic.yaml` runs on a disposable
checkout and changes all six deployment-target entries to 10.15 immediately
before building. It verifies the generated Info.plist, Swift package, Runner,
one-shot helper, Flutter framework, and Dart application framework. It also
requires every executable to contain both Intel and Apple Silicon slices.

Flutter 3.38.9 is pinned because it contains Dart 3.10.8 and a Flutter engine
compatible with the Catalina variant. The shared Dart source therefore keeps a
minimum SDK constraint of Dart 3.10.8 while the normal local build can continue
using the current Flutter stable release.

The generated ZIP is ad-hoc signed and intended for compatibility testing. A
publicly distributed build still needs a Developer ID certificate and Apple
notarization configured in Codemagic.

Source compatibility rules:

- Keep the bridge and mutation engine free of APIs introduced after macOS 10.15.
- Do not fork the Dart mutation contract between build variants.
- Never use `sudo`, Terminal, a LaunchDaemon, a Login Item, or an elevated full
  application.
- Keep each authorization one-shot: start the helper for one confirmed
  transaction and let the process terminate as soon as it returns JSON.
- Keep destinations fixed inside the helper and verify the private request file
  digest before any record is changed.
