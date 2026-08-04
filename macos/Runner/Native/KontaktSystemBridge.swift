import Cocoa
import CryptoKit
import FlutterMacOS

final class KontaktSystemBridge {
  private static let channelName = "com.juanayala.kontaktLibraryManager/system"
  private static let helperExecutableName = "KontaktLibraryHelper"
  private static let maximumRequestSize = 2_500_000

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "helperStatus":
        result(helperStatus())
      case "enableHelper":
        // The helper is bundled and invoked only for a confirmed mutation. It
        // is never installed, registered, or left running in the background.
        result(helperStatus())
      case "selectDirectories":
        selectDirectories(arguments: call.arguments, result: result)
      case "saveClassicOrder":
        saveClassicOrder(arguments: call.arguments, result: result)
      case "executeMutation":
        executeMutation(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func helperURL() -> URL? {
    Bundle.main.resourceURL?.appendingPathComponent(helperExecutableName)
  }

  private static func helperStatus() -> String {
    guard let helper = helperURL(),
          FileManager.default.isExecutableFile(atPath: helper.path)
    else {
      return "unavailable"
    }
    return "enabled"
  }

  private static func selectDirectories(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    let values = arguments as? [String: Any]
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = values?["allowMultiple"] as? Bool ?? false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.prompt = "Select"
    if panel.runModal() == .OK {
      result(panel.urls.map(\.path))
    } else {
      result([String]())
    }
  }

  private static func saveClassicOrder(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    let kontaktIsRunning = NSWorkspace.shared.runningApplications.contains {
      guard $0.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
        return false
      }
      let name = $0.localizedName?.lowercased() ?? ""
      let identifier = $0.bundleIdentifier?.lowercased() ?? ""
      let versionSuffix = name.hasPrefix("kontakt ")
        ? name.dropFirst("kontakt ".count)
        : Substring()
      let isVersionedKontakt = !versionSuffix.isEmpty &&
        versionSuffix.allSatisfy { $0.isNumber || $0 == "." }
      return name == "kontakt" || isVersionedKontakt ||
        identifier.contains("native-instruments.kontakt")
    }
    guard !kontaktIsRunning else {
      result(
        FlutterError(
          code: "kontakt_running",
          message: "Close Kontakt and any DAW using Kontakt before saving the classic library order.",
          details: nil
        )
      )
      return
    }

    guard let values = arguments as? [String: Any],
          let rawEntries = values["entries"] as? [[String: Any]],
          rawEntries.count <= 10_000
    else {
      result(
        FlutterError(
          code: "invalid_classic_order",
          message: "The classic library order is invalid.",
          details: nil
        )
      )
      return
    }

    var entries = [(regKey: String, name: String, snpid: String?, index: Int)]()
    var regKeys = Set<String>()
    var indexes = Set<Int>()
    for rawEntry in rawEntries {
      guard let regKey = safePreferenceComponent(rawEntry["regKey"] as? String),
            let name = safePreferenceComponent(rawEntry["name"] as? String),
            let index = rawEntry["userListIndex"] as? Int,
            index >= 1,
            index <= rawEntries.count,
            regKeys.insert(regKey.lowercased()).inserted,
            indexes.insert(index).inserted
      else {
        result(
          FlutterError(
            code: "invalid_classic_order",
            message: "The classic library order contains unsafe or duplicate values.",
            details: nil
          )
        )
        return
      }
      let snpid = safePreferenceComponent(rawEntry["snpid"] as? String)
      entries.append((regKey, name, snpid, index))
    }

    for entry in entries {
      let domain = "com.native-instruments.\(entry.regKey)"
      guard let preferences = UserDefaults(suiteName: domain) else {
        result(
          FlutterError(
            code: "classic_order_write_failed",
            message: "The preferences for \(entry.name) could not be opened.",
            details: nil
          )
        )
        return
      }
      preferences.set(entry.index, forKey: "UserListIndex")
      preferences.set(entry.name, forKey: "Name")
      preferences.set(entry.regKey, forKey: "RegKey")
      if let snpid = entry.snpid {
        preferences.set(snpid, forKey: "SNPID")
      }
      guard preferences.synchronize() else {
        result(
          FlutterError(
            code: "classic_order_write_failed",
            message: "The order for \(entry.name) could not be saved.",
            details: nil
          )
        )
        return
      }
      guard preferences.integer(forKey: "UserListIndex") == entry.index else {
        result(
          FlutterError(
            code: "classic_order_write_failed",
            message: "The saved order for \(entry.name) could not be verified.",
            details: nil
          )
        )
        return
      }
    }

    // The classic A-Z switch overrides UserListIndex. Disable it for all
    // supported Kontakt generations so the saved custom order is visible.
    for domain in [
      "com.native-instruments.Kontakt",
      "com.native-instruments.Kontakt 7",
      "com.native-instruments.Kontakt 8",
    ] {
      let preferences = UserDefaults(suiteName: domain)
      preferences?.set(false, forKey: "browserLibsAZSort")
      preferences?.synchronize()
    }
    result(nil)
  }

  private static func safePreferenceComponent(_ value: String?) -> String? {
    guard let value,
          !value.isEmpty,
          value.utf8.count <= 255,
          value != ".",
          value != "..",
          !value.contains("/"),
          !value.contains("\\"),
          !value.contains("\n"),
          !value.contains("\r"),
          !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      return nil
    }
    return value
  }

  private static func executeMutation(
    arguments: Any?,
    result: @escaping FlutterResult
  ) {
    guard let helper = helperURL(),
          FileManager.default.isExecutableFile(atPath: helper.path)
    else {
      result(
        FlutterError(
          code: "helper_unavailable",
          message: "The one-time administrator helper is missing from the application bundle.",
          details: nil
        )
      )
      return
    }
    guard let request = arguments as? [String: Any],
          JSONSerialization.isValidJSONObject(request)
    else {
      result(
        FlutterError(
          code: "invalid_mutation_request",
          message: "The mutation request is invalid.",
          details: nil
        )
      )
      return
    }

    do {
      let requestData = try JSONSerialization.data(withJSONObject: request)
      guard requestData.count <= maximumRequestSize else {
        result(
          FlutterError(
            code: "mutation_request_too_large",
            message: "The mutation request is too large.",
            details: nil
          )
        )
        return
      }
      runOneShotHelper(
        helper: helper,
        requestData: requestData,
        result: result
      )
    } catch {
      result(
        FlutterError(
          code: "mutation_encoding_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private static func runOneShotHelper(
    helper: URL,
    requestData: Data,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let fileManager = FileManager.default
      // The elevated process must be able to traverse the request directory.
      // FileManager.temporaryDirectory points into the user's protected
      // /var/folders tree, which can be denied after the authorization context
      // changes. A random 0700 directory in the system temporary root remains
      // private while being reachable by the one-shot root process.
      let temporaryDirectory = URL(
        fileURLWithPath: "/private/tmp",
        isDirectory: true
      ).appendingPathComponent(
        "kontakt-library-manager-\(UUID().uuidString)",
        isDirectory: true
      )
      let requestURL = temporaryDirectory.appendingPathComponent("request.json")

      do {
        try fileManager.createDirectory(
          at: temporaryDirectory,
          withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700]
        )
        guard fileManager.createFile(
          atPath: requestURL.path,
          contents: requestData,
          attributes: [.posixPermissions: 0o600]
        ) else {
          throw BridgeError.couldNotCreateRequest
        }
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let digest = SHA256.hash(data: requestData)
          .map { String(format: "%02x", $0) }
          .joined()
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
          "-e",
          administratorScript,
          "--",
          helper.path,
          requestURL.path,
          digest,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()
        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
          let wasCancelled = errorMessage?.contains("(-128)") == true
          throw BridgeError.helperFailed(
            code: wasCancelled ? "authorization_cancelled" : "mutation_failed",
            message: errorMessage?.isEmpty == false
              ? errorMessage!
              : "The administrator operation failed."
          )
        }
        guard let response = try JSONSerialization.jsonObject(with: outputData)
          as? [String: Any]
        else {
          throw BridgeError.invalidHelperResponse
        }

        DispatchQueue.main.async { result(response) }
      } catch let error as BridgeError {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: error.code,
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "one_shot_helper_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private static let administratorScript = """
  on run argv
    set helperPath to item 1 of argv
    set requestPath to item 2 of argv
    set requestDigest to item 3 of argv
    set commandText to quoted form of helperPath & " --request " & quoted form of requestPath & " --sha256 " & quoted form of requestDigest
    return do shell script commandText with administrator privileges
  end run
  """
}

private enum BridgeError: LocalizedError {
  case couldNotCreateRequest
  case invalidHelperResponse
  case helperFailed(code: String, message: String)

  var code: String {
    switch self {
    case .couldNotCreateRequest:
      return "request_file_failed"
    case .invalidHelperResponse:
      return "invalid_helper_response"
    case .helperFailed(let code, _):
      return code
    }
  }

  var errorDescription: String? {
    switch self {
    case .couldNotCreateRequest:
      return "The private mutation request could not be created."
    case .invalidHelperResponse:
      return "The administrator helper returned invalid data."
    case .helperFailed(_, let message):
      return message
    }
  }
}
