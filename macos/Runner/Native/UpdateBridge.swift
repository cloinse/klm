import FlutterMacOS
import Foundation
import Sparkle

@MainActor
final class UpdateBridge: NSObject, SPUUpdaterDelegate {
  private static let channelName =
    "com.juanayala.kontaktLibraryManager/updates"

  private let channel: FlutterMethodChannel
  private var updaterController: SPUStandardUpdaterController?
  private var probeResult: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )

    let feedURL = Bundle.main.object(
      forInfoDictionaryKey: "SUFeedURL"
    ) as? String ?? ""
    let publicKey = Bundle.main.object(
      forInfoDictionaryKey: "SUPublicEDKey"
    ) as? String ?? ""
    let configured = URL(string: feedURL)?.scheme == "https"
      && !publicKey.isEmpty
      && !publicKey.contains("$(")

    super.init()

    if configured {
      updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
      )
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
        guard let updaterController = self.updaterController else {
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
        updaterController.updater.checkForUpdateInformation()
      case "checkForUpdates":
        guard let updaterController = self.updaterController else {
          result(
            FlutterError(
              code: "updater_not_configured",
              message: "The update service is not configured.",
              details: nil
            )
          )
          return
        }
        updaterController.checkForUpdates(nil)
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
    completeProbe(available: true)
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
    completeProbe(available: false)
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

  private func completeProbe(available: Bool) {
    guard let result = probeResult else { return }
    probeResult = nil
    result(available)
  }

  private var infoPayload: [String: Any] {
    let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? ""
    return [
      "currentVersion": version,
      "configured": updaterController != nil,
    ]
  }
}
