import FlutterMacOS
import Foundation
import Sparkle

@MainActor
final class UpdateBridge: NSObject {
  private static let channelName =
    "com.juanayala.kontaktLibraryManager/updates"

  private let channel: FlutterMethodChannel
  private let updaterController: SPUStandardUpdaterController?

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

    updaterController = configured
      ? SPUStandardUpdaterController(
          startingUpdater: true,
          updaterDelegate: nil,
          userDriverDelegate: nil
        )
      : nil

    super.init()

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
