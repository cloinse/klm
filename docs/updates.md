# Application updates

KLM uses Sparkle 2 on macOS with ad-hoc application signatures and Ed25519
update signatures. The updater is manual and runs only while KLM is open.

## Distribution rules

- Release and Profile builds only run from `/Applications`.
- Debug builds may run from the build directory for local development.
- The DMG presents a fixed Finder layout with the app, an installation arrow,
  and an `Applications` link.
- The layout metadata is generated without Finder or Apple Events, so the same
  visual installer can be built in headless Codemagic workers.
- The packaging script creates a temporary Python environment with hash-pinned
  `dmgbuild` dependencies; nothing is installed globally on the build machine.
- The Kontakt administrator helper remains independent from Sparkle and
  Flutter frameworks.
- Every distributed build uses the single signed legacy appcast.

## Private key

The update private key is stored in the developer login Keychain under the
account `com.juanayala.kontaktLibraryManager`. A local exported copy may exist
at `.secrets/KLM_SPARKLE_PRIVATE_KEY`; `.secrets/` is ignored by Git.

For Codemagic, create the secret variable `KLM_SPARKLE_PRIVATE_KEY` with the
exact contents of that file. Never commit or print this value.

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
