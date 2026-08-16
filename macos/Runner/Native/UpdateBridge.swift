import FlutterMacOS
import Foundation
import Sparkle

@MainActor
final class InstallOnlyUpdateUserDriver: NSObject, SPUUserDriver {
  func show(
    _ request: SPUUpdatePermissionRequest,
    reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    reply(
      SUUpdatePermissionResponse(
        automaticUpdateChecks: false,
        sendSystemProfile: false
      )
    )
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

  func showUpdateFound(
    with appcastItem: SUAppcastItem,
    state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    reply(.install)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    acknowledgement()
  }

  func showUpdaterError(
    _ error: Error,
    acknowledgement: @escaping () -> Void
  ) {
    acknowledgement()
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {}

  func showDownloadDidReceiveExpectedContentLength(
    _ expectedContentLength: UInt64
  ) {}

  func showDownloadDidReceiveData(ofLength length: UInt64) {}

  func showDownloadDidStartExtractingUpdate() {}

  func showExtractionReceivedProgress(_ progress: Double) {}

  func showReady(
    toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    reply(.install)
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {}

  func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool,
    acknowledgement: @escaping () -> Void
  ) {
    acknowledgement()
  }

  func showUpdateInFocus() {}

  func dismissUpdateInstallation() {}
}

@MainActor
final class UpdateBridge: NSObject, SPUUpdaterDelegate {
  private static let channelName =
    "com.juanayala.kontaktLibraryManager/updates"

  private let channel: FlutterMethodChannel
  private let userDriver = InstallOnlyUpdateUserDriver()
  private var updater: SPUUpdater?
  private var probeResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )

    let feedURL =
      Bundle.main.object(
        forInfoDictionaryKey: "SUFeedURL"
      ) as? String ?? ""
    let publicKey =
      Bundle.main.object(
        forInfoDictionaryKey: "SUPublicEDKey"
      ) as? String ?? ""
    let configured =
      URL(string: feedURL)?.scheme == "https"
      && !publicKey.isEmpty
      && !publicKey.contains("$(")

    super.init()

    if configured {
      let updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: userDriver,
        delegate: self
      )
      do {
        try updater.start()
        self.updater = updater
      } catch {
        self.updater = nil
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "updater_unavailable",
            message: "The update service is unavailable.",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "getInfo":
        result(self.infoPayload)
      case "probeForUpdates":
        guard let updater = self.updater else {
          result(false)
          return
        }
        guard self.probeResult == nil else {
          result(
            FlutterError(
              code: "update_check_in_progress",
              message: "An update check is already in progress.",
              details: nil
            )
          )
          return
        }
        self.probeResult = result
        updater.checkForUpdateInformation()
      case "installUpdate":
        guard let updater = self.updater else {
          result(
            FlutterError(
              code: "updater_not_configured",
              message: "The update service is not configured.",
              details: nil
            )
          )
          return
        }
        updater.checkForUpdates()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func updater(
    _ updater: SPUUpdater,
    didFindValidUpdate item: SUAppcastItem
  ) {
    completeProbe(item: item)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    completeProbe(item: nil)
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    guard let result = probeResult else { return }
    probeResult = nil
    result(
      FlutterError(
        code: "update_check_failed",
        message: error.localizedDescription,
        details: nil
      )
    )
  }

  private func completeProbe(item: SUAppcastItem?) {
    guard let result = probeResult else { return }
    probeResult = nil
    guard let item else {
      result(nil)
      return
    }
    result([
      "version": item.displayVersionString,
      "build": item.versionString,
      "releaseNotes": item.itemDescription ?? "",
    ])
  }

  private var infoPayload: [String: Any] {
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? ""
    let build =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleVersion"
      ) as? String ?? ""
    return [
      "currentVersion": version,
      "currentBuild": build,
      "configured": updater != nil,
    ]
  }
}
