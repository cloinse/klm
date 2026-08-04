import Foundation

private enum MutationError: LocalizedError {
  case invalidRequest(String)
  case unsafePath(String)
  case missingRecord(String)

  var errorDescription: String? {
    switch self {
    case .invalidRequest(let message):
      return "Invalid request: \(message)"
    case .unsafePath(let path):
      return "A symbolic link or unsafe path was rejected: \(path)"
    case .missingRecord(let path):
      return "A required record is missing: \(path)"
    }
  }
}

enum MutationTransaction {
  static func execute(requestData: Data) throws -> [String: Any] {
    try execute(requestData: requestData, locations: .system)
  }

  static func execute(
    requestData: Data,
    locations: MutationLocations
  ) throws -> [String: Any] {
    guard requestData.count <= 2_500_000,
          let object = try JSONSerialization.jsonObject(with: requestData)
            as? [String: Any],
          object["version"] as? Int == 1,
          let operation = object["operation"] as? String,
          let name = safeComponent(object["name"] as? String),
          let regKey = safeComponent(object["regKey"] as? String)
    else {
      throw MutationError.invalidRequest("missing or unsafe fields")
    }

    let serviceURL = locations.serviceCenter.appendingPathComponent("\(name).xml")
    let plistURL = locations.preferences.appendingPathComponent(
      "com.native-instruments.\(regKey).plist"
    )
    let jsonURL = locations.installedProducts.appendingPathComponent("\(name).json")

    let mutations: [FileMutation]
    switch operation {
    case "upsert":
      mutations = try upsertMutations(
        object,
        serviceURL: serviceURL,
        plistURL: plistURL,
        jsonURL: jsonURL
      )
    case "relocate":
      mutations = try relocationMutations(
        object,
        plistURL: plistURL,
        jsonURL: jsonURL
      )
    case "remove":
      mutations = [
        FileMutation(url: serviceURL, data: nil),
        FileMutation(url: plistURL, data: nil),
        FileMutation(url: jsonURL, data: nil),
      ]
    default:
      throw MutationError.invalidRequest("unknown operation")
    }

    let changedPaths = try apply(mutations)
    return [
      "operation": operation,
      "libraryName": name,
      "changedPaths": changedPaths,
    ]
  }

  private static func upsertMutations(
    _ object: [String: Any],
    serviceURL: URL,
    plistURL: URL,
    jsonURL: URL
  ) throws -> [FileMutation] {
    guard let name = safeComponent(object["name"] as? String),
          let regKey = safeComponent(object["regKey"] as? String),
          let snpid = safeComponent(object["snpid"] as? String),
          let contentPath = validContentPath(object["contentPath"] as? String),
          let xml = object["productHintsXml"] as? String,
          xml.utf8.count <= 2_000_000,
          xml.contains("<ProductHints"),
          xml.contains("</ProductHints>"),
          !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
          !xml.localizedCaseInsensitiveContains("<!ENTITY")
    else {
      throw MutationError.invalidRequest("invalid ProductHints or content path")
    }
    try validateProductHints(xml, name: name, regKey: regKey, snpid: snpid)

    var plist: [String: Any] = [
      "ContentDir": contentPath,
      "RegKey": regKey,
      "SNPID": snpid,
      "Name": name,
      "Visibility": object["visibility"] as? Int ?? 3,
    ]
    copyString("hu", to: "HU", from: object, into: &plist)
    copyString("jdx", to: "JDX", from: object, into: &plist)
    copyString("upid", to: "UPID", from: object, into: &plist)
    copyString("authSystem", to: "AuthSystem", from: object, into: &plist)

    let plistData = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    let jsonData = try JSONSerialization.data(
      withJSONObject: ["ContentDir": contentPath],
      options: [.prettyPrinted, .sortedKeys]
    )
    guard let xmlData = xml.data(using: .utf8) else {
      throw MutationError.invalidRequest("ProductHints is not UTF-8")
    }
    return [
      FileMutation(url: serviceURL, data: xmlData),
      FileMutation(url: plistURL, data: plistData),
      FileMutation(url: jsonURL, data: jsonData),
    ]
  }

  private static func relocationMutations(
    _ object: [String: Any],
    plistURL: URL,
    jsonURL: URL
  ) throws -> [FileMutation] {
    guard let contentPath = validContentPath(object["contentPath"] as? String),
          let name = safeComponent(object["name"] as? String),
          let regKey = safeComponent(object["regKey"] as? String)
    else {
      throw MutationError.invalidRequest("invalid relocation path")
    }

    var plist: [String: Any]
    if let data = try? Data(contentsOf: plistURL),
       let existing = try PropertyListSerialization.propertyList(
         from: data,
         options: [],
         format: nil
       ) as? [String: Any] {
      plist = existing
    } else {
      guard let snpid = safeComponent(object["snpid"] as? String) else {
        throw MutationError.missingRecord(plistURL.path)
      }
      plist = ["Name": name, "RegKey": regKey, "SNPID": snpid]
    }
    plist["ContentDir"] = contentPath
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    let jsonData = try JSONSerialization.data(
      withJSONObject: ["ContentDir": contentPath],
      options: [.prettyPrinted, .sortedKeys]
    )
    return [
      FileMutation(url: plistURL, data: plistData),
      FileMutation(url: jsonURL, data: jsonData),
    ]
  }

  private static func apply(_ mutations: [FileMutation]) throws -> [String] {
    let manager = FileManager.default
    let directories = Set(
      mutations.compactMap {
        $0.data == nil ? nil : $0.url.deletingLastPathComponent()
      }
    )
    for directory in directories {
      try rejectSymbolicLinks(in: directory)
      try manager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
      )
      try rejectSymbolicLinks(in: directory)
    }

    var backups = [URL: BackupState]()
    do {
      for mutation in mutations {
        try rejectSymbolicLinks(in: mutation.url)
        backups[mutation.url] = manager.fileExists(atPath: mutation.url.path)
          ? .data(try Data(contentsOf: mutation.url))
          : .missing
        if let data = mutation.data {
          try data.write(to: mutation.url, options: .atomic)
          try manager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: mutation.url.path
          )
        } else if manager.fileExists(atPath: mutation.url.path) {
          try manager.removeItem(at: mutation.url)
        }
      }
    } catch {
      for (url, backup) in backups {
        switch backup {
        case .data(let data):
          try? data.write(to: url, options: .atomic)
        case .missing:
          try? manager.removeItem(at: url)
        }
      }
      throw error
    }
    return mutations.map(\.url.path)
  }

  private static func rejectSymbolicLinks(in url: URL) throws {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    // The destinations are built from fixed absolute roots and validated file
    // components. Using URL.pathComponents preserves /private/var for isolated
    // tests; standardizedFileURL rewrites it to the /var compatibility symlink.
    for component in url.pathComponents.dropFirst() {
      current.appendPathComponent(component)
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(
        atPath: current.path,
        isDirectory: &isDirectory
      ) else {
        continue
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
      if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
        throw MutationError.unsafePath(current.path)
      }
    }
  }

  private static func validContentPath(_ value: String?) -> String? {
    guard let value,
          value.utf8.count <= 4096,
          value.hasPrefix("/"),
          FileManager.default.fileExists(atPath: value)
    else {
      return nil
    }
    return URL(fileURLWithPath: value).standardizedFileURL.path
  }

  private static func safeComponent(_ value: String?) -> String? {
    guard let value,
          !value.isEmpty,
          value != ".",
          value != "..",
          value.utf8.count <= 255,
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

  private static func validateProductHints(
    _ xml: String,
    name: String,
    regKey: String,
    snpid: String
  ) throws {
    let document = try XMLDocument(xmlString: xml, options: [.nodePreserveAll])
    let products = try document.nodes(forXPath: "/ProductHints/Product")
    guard products.count == 1,
          try document.nodes(forXPath: "/ProductHints/Product/Name")
            .first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == name,
          try document.nodes(forXPath: "/ProductHints/Product/RegKey")
            .first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == regKey,
          try document.nodes(forXPath: "/ProductHints/Product/SNPID")
            .first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == snpid
    else {
      throw MutationError.invalidRequest("ProductHints fields do not match")
    }
  }

  private static func copyString(
    _ sourceKey: String,
    to destinationKey: String,
    from source: [String: Any],
    into destination: inout [String: Any]
  ) {
    if let value = source[sourceKey] as? String, !value.isEmpty {
      destination[destinationKey] = value
    }
  }
}

struct MutationLocations {
  let serviceCenter: URL
  let preferences: URL
  let installedProducts: URL

  static let system = MutationLocations(
    serviceCenter: URL(
      fileURLWithPath: "/Library/Application Support/Native Instruments/Service Center",
      isDirectory: true
    ),
    preferences: URL(
      fileURLWithPath: "/Library/Preferences",
      isDirectory: true
    ),
    installedProducts: URL(
      fileURLWithPath: "/Users/Shared/Native Instruments/installed_products",
      isDirectory: true
    )
  )
}

private struct FileMutation {
  let url: URL
  let data: Data?
}

private enum BackupState {
  case missing
  case data(Data)
}
