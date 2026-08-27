import Foundation

private let maximumInstalledProductsJSONSize = 2_500_000

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
          object["version"] as? Int == 1
    else {
      throw MutationError.invalidRequest("missing or unsafe fields")
    }

    if let operations = object["operations"] as? [[String: Any]] {
      guard !operations.isEmpty, operations.count <= 1_000 else {
        throw MutationError.invalidRequest("invalid batch size")
      }
      let plans = try operations.map {
        try mutationPlan($0, locations: locations)
      }
      let mutations = plans.flatMap(\.mutations)
      var targetIndexes: [String: Int] = [:]
      var uniqueMutations: [FileMutation] = []
      for mutation in mutations {
        let targetPath = mutation.url.path.lowercased()
        if let existingIndex = targetIndexes[targetPath] {
          guard uniqueMutations[existingIndex].data == mutation.data else {
            throw MutationError.invalidRequest("conflicting mutation targets")
          }
          continue
        }
        targetIndexes[targetPath] = uniqueMutations.count
        uniqueMutations.append(mutation)
      }
      _ = try apply(uniqueMutations)
      return [
        "operation": "batch",
        "results": plans.map { plan in
          [
            "operation": plan.operation,
            "libraryName": plan.name,
            "changedPaths": plan.mutations.map { $0.url.path },
          ]
        },
      ]
    }

    let plan = try mutationPlan(object, locations: locations)
    let changedPaths = try apply(plan.mutations)
    return [
      "operation": plan.operation,
      "libraryName": plan.name,
      "changedPaths": changedPaths,
    ]
  }

  private static func mutationPlan(
    _ object: [String: Any],
    locations: MutationLocations
  ) throws -> MutationPlan {
    guard let operation = object["operation"] as? String,
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
    return MutationPlan(operation: operation, name: name, mutations: mutations)
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

    let existingPlist = existingPropertyList(at: plistURL)
    var plist = existingPlist?.value ?? [:]
    plist["ContentDir"] = contentPath
    plist["RegKey"] = regKey
    plist["SNPID"] = snpid
    plist["Name"] = name
    plist["Visibility"] = object["visibility"] as? Int ?? 3
    copyString("hu", to: "HU", from: object, into: &plist)
    copyString("jdx", to: "JDX", from: object, into: &plist)
    copyString("upid", to: "UPID", from: object, into: &plist)
    copyString("authSystem", to: "AuthSystem", from: object, into: &plist)

    let plistData = try serializePropertyList(
      plist,
      preserving: existingPlist
    )
    let existingJSON = try existingJSONDictionary(at: jsonURL)
    var json = existingJSON?.value ?? [:]
    json["ContentDir"] = contentPath
    let jsonData = try serializeJSON(
      json,
      preserving: existingJSON,
      contentPath: contentPath
    )
    guard let candidateXMLData = xml.data(using: .utf8) else {
      throw MutationError.invalidRequest("ProductHints is not UTF-8")
    }
    let xmlData: Data
    if let existingXMLData = try? Data(contentsOf: serviceURL),
       productHintsMatch(
         existingXMLData,
         name: name,
         regKey: regKey,
         snpid: snpid
       ) {
      xmlData = existingXMLData
    } else {
      xmlData = candidateXMLData
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

    let existingPlist = existingPropertyList(at: plistURL)
    var plist: [String: Any]
    if let existingPlist {
      plist = existingPlist.value
    } else {
      guard let snpid = safeComponent(object["snpid"] as? String) else {
        throw MutationError.missingRecord(plistURL.path)
      }
      plist = ["Name": name, "RegKey": regKey, "SNPID": snpid]
    }
    plist["ContentDir"] = contentPath
    let plistData = try serializePropertyList(
      plist,
      preserving: existingPlist
    )
    let existingJSON = try existingJSONDictionary(at: jsonURL)
    var json = existingJSON?.value ?? [:]
    json["ContentDir"] = contentPath
    let jsonData = try serializeJSON(
      json,
      preserving: existingJSON,
      contentPath: contentPath
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
          !value.unicodeScalars.contains(
            where: CharacterSet.controlCharacters.contains
          ),
          !value.split(separator: "/").contains(where: {
            $0 == "." || $0 == ".."
          }),
          FileManager.default.fileExists(atPath: value)
    else {
      return nil
    }
    // The caller already resolves the selected directory. Preserve that exact
    // representation so an unchanged /private/var path is not rewritten as
    // /var and a healthy Native Access record remains byte-for-byte intact.
    return value
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
          isKontaktProductHints(document),
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

  private static func isKontaktProductHints(_ document: XMLDocument) -> Bool {
    func values(_ xpath: String) -> [String] {
      let nodes = (try? document.nodes(forXPath: xpath)) ?? []
      return nodes.compactMap {
        $0.stringValue?
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
      }.filter { !$0.isEmpty }
    }

    let type = values("/ProductHints/Product/Type").first
    if type == "plugin" { return false }

    let applications = values(
      "/ProductHints/Product/Relevance/Application"
    )
    if !applications.isEmpty {
      return applications.contains("kontakt")
    }
    if let poweredBy = values("/ProductHints/Product/PoweredBy").first {
      return poweredBy.contains("kontakt")
    }
    if let icon = values("/ProductHints/Product/Icon").first,
       icon.contains("kontakt") {
      return true
    }
    return type == "content"
  }

  private static func productHintsMatch(
    _ data: Data,
    name: String,
    regKey: String,
    snpid: String
  ) -> Bool {
    guard data.count <= 2_000_000,
          let xml = String(data: data, encoding: .utf8),
          !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
          !xml.localizedCaseInsensitiveContains("<!ENTITY")
    else {
      return false
    }
    do {
      try validateProductHints(xml, name: name, regKey: regKey, snpid: snpid)
      return true
    } catch {
      return false
    }
  }

  private static func existingPropertyList(
    at url: URL
  ) -> (data: Data, value: [String: Any])? {
    guard let data = try? Data(contentsOf: url),
          let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
          ),
          let value = object as? [String: Any]
    else {
      return nil
    }
    return (data, value)
  }

  private static func existingJSONDictionary(
    at url: URL
  ) throws -> (data: Data, value: [String: Any])? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    try rejectSymbolicLinks(in: url)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    ), !isDirectory.boolValue else {
      throw MutationError.invalidRequest(
        "The installed_products JSON target is not a regular file."
      )
    }

    guard let attributes = try? FileManager.default.attributesOfItem(
      atPath: url.path
    ),
    let size = (attributes[.size] as? NSNumber)?.int64Value,
    size >= 0,
    size <= Int64(maximumInstalledProductsJSONSize)
    else {
      throw MutationError.invalidRequest(
        "The existing installed_products JSON could not be backed up."
      )
    }

    guard let data = try? Data(contentsOf: url) else {
      throw MutationError.invalidRequest(
        "The existing installed_products JSON could not be read."
      )
    }
    guard data.count <= maximumInstalledProductsJSONSize else {
      throw MutationError.invalidRequest(
        "The existing installed_products JSON could not be backed up."
      )
    }

    // JSONSerialization does not consistently accept an UTF-8 BOM across
    // supported macOS releases. Windows accepts one, so remove it only for
    // validation while retaining the original bytes for the patch below.
    let validationData: Data
    if data.count >= 3,
       data[data.startIndex] == 0xEF,
       data[data.startIndex + 1] == 0xBB,
       data[data.startIndex + 2] == 0xBF {
      validationData = data.dropFirst(3)
    } else {
      validationData = data
    }

    guard let object = try? JSONSerialization.jsonObject(with: validationData),
          let value = object as? [String: Any]
    else {
      throw MutationError.invalidRequest(
        "The existing installed_products JSON is invalid or unsupported."
      )
    }
    return (data, value)
  }

  private static func serializePropertyList(
    _ value: [String: Any],
    preserving existing: (data: Data, value: [String: Any])?
  ) throws -> Data {
    if let existing,
       NSDictionary(dictionary: existing.value).isEqual(
         NSDictionary(dictionary: value)
       ) {
      return existing.data
    }
    return try PropertyListSerialization.data(
      fromPropertyList: value,
      format: .xml,
      options: 0
    )
  }

  private static func serializeJSON(
    _ value: [String: Any],
    preserving existing: (data: Data, value: [String: Any])?,
    contentPath: String
  ) throws -> Data {
    if let existing,
       NSDictionary(dictionary: existing.value).isEqual(
         NSDictionary(dictionary: value)
       ) {
      return existing.data
    }

    if let existing {
      guard let patched = JSONContentDirectoryPatcher.update(
        existing.data,
        contentPath: contentPath
      ) else {
        throw MutationError.invalidRequest(
          "The existing installed_products JSON is invalid or unsupported."
        )
      }
      return patched
    }

    // A missing installed_products record has no fields to preserve. Keep the
    // same compact representation emitted by the Windows native helper.
    return Data(
      "{\"ContentDir\":\"\(JSONContentDirectoryPatcher.escape(contentPath))\"}"
        .utf8
    )
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

/// Replaces the ContentDir member in an existing JSON object without
/// reserializing the document. This intentionally mirrors the Windows native
/// helper: only JSON whitespace and string syntax are parsed, while every
/// other byte is retained exactly as it was on disk.
private enum JSONContentDirectoryPatcher {
  private struct ParsedString {
    let end: Int
    let value: String
  }

  static func update(_ data: Data, contentPath: String) -> Data? {
    var bytes = Array(data)
    var root = skipWhitespace(bytes, from: 0)
    if bytes.count >= 3,
       bytes[0] == 0xEF,
       bytes[1] == 0xBB,
       bytes[2] == 0xBF {
      root = skipWhitespace(bytes, from: 3)
    }
    guard root < bytes.count, bytes[root] == Character("{").asciiValue else {
      return nil
    }

    let replacement = Array(
      "\"\(escape(contentPath))\"".utf8
    )
    var position = root + 1
    var hasMember = false
    var foundContentDirectory = false
    var expectMember = false
    var closingBrace: Int?

    while true {
      position = skipWhitespace(bytes, from: position)
      guard position < bytes.count else { return nil }
      if bytes[position] == Character("}").asciiValue {
        if expectMember { return nil }
        closingBrace = position
        break
      }

      guard let key = parseString(bytes, from: position) else {
        return nil
      }
      let keyStart = position
      var keyEnd = key.end
      if key.value == "contentDir" {
        let canonicalKey = Array("\"ContentDir\"".utf8)
        bytes.replaceSubrange(keyStart..<keyEnd, with: canonicalKey)
        keyEnd = keyStart + canonicalKey.count
      }
      position = skipWhitespace(bytes, from: keyEnd)
      guard position < bytes.count,
            bytes[position] == Character(":").asciiValue
      else {
        return nil
      }
      position = skipWhitespace(bytes, from: position + 1)
      let valueStart = position
      guard let valueEnd = skipValue(bytes, from: valueStart) else {
        return nil
      }

      expectMember = false
      if key.value == "ContentDir" || key.value == "contentDir" {
        if foundContentDirectory { return nil }
        foundContentDirectory = true
        bytes.replaceSubrange(valueStart..<valueEnd, with: replacement)
        position = valueStart + replacement.count
      } else {
        position = valueEnd
      }
      hasMember = true
      position = skipWhitespace(bytes, from: position)
      guard position < bytes.count else { return nil }
      if bytes[position] == Character(",").asciiValue {
        position += 1
        expectMember = true
        continue
      }
      if bytes[position] == Character("}").asciiValue {
        expectMember = false
        closingBrace = position
        break
      }
      return nil
    }

    guard let closingBrace,
          skipWhitespace(bytes, from: closingBrace + 1) == bytes.count
    else {
      return nil
    }

    if !foundContentDirectory {
      var insertion = [UInt8]()
      if hasMember { insertion.append(Character(",").asciiValue!) }
      insertion.append(contentsOf: "\"ContentDir\":\"".utf8)
      insertion.append(contentsOf: escape(contentPath).utf8)
      insertion.append(Character("\"").asciiValue!)
      bytes.insert(contentsOf: insertion, at: closingBrace)
    }
    return Data(bytes)
  }

  static func escape(_ value: String) -> String {
    let hex = Array("0123456789abcdef".utf8)
    var escaped = [UInt8]()
    escaped.reserveCapacity(value.utf8.count + 8)
    for byte in value.utf8 {
      switch byte {
      case 0x22:
        escaped.append(contentsOf: [0x5C, 0x22])
      case 0x5C:
        escaped.append(contentsOf: [0x5C, 0x5C])
      case 0x08:
        escaped.append(contentsOf: [0x5C, 0x62])
      case 0x0C:
        escaped.append(contentsOf: [0x5C, 0x66])
      case 0x0A:
        escaped.append(contentsOf: [0x5C, 0x6E])
      case 0x0D:
        escaped.append(contentsOf: [0x5C, 0x72])
      case 0x09:
        escaped.append(contentsOf: [0x5C, 0x74])
      case 0x00...0x1F:
        escaped.append(contentsOf: [0x5C, 0x75, 0x30, 0x30])
        escaped.append(hex[Int(byte >> 4)])
        escaped.append(hex[Int(byte & 0x0F)])
      default:
        escaped.append(byte)
      }
    }
    return String(decoding: escaped, as: UTF8.self)
  }

  private static func skipWhitespace(_ bytes: [UInt8], from start: Int) -> Int {
    var position = start
    while position < bytes.count {
      switch bytes[position] {
      case 0x20, 0x09, 0x0A, 0x0D:
        position += 1
      default:
        return position
      }
    }
    return position
  }

  private static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39: return byte - 0x30
    case 0x41...0x46: return byte - 0x41 + 10
    case 0x61...0x66: return byte - 0x61 + 10
    default: return nil
    }
  }

  private static func parseString(
    _ bytes: [UInt8],
    from start: Int
  ) -> ParsedString? {
    guard start < bytes.count, bytes[start] == Character("\"").asciiValue
    else {
      return nil
    }

    var value = [UInt8]()
    var position = start + 1
    while position < bytes.count {
      let byte = bytes[position]
      if byte == Character("\"").asciiValue {
        return ParsedString(
          end: position + 1,
          value: String(decoding: value, as: UTF8.self)
        )
      }
      if byte < 0x20 { return nil }
      if byte != Character("\\").asciiValue {
        value.append(byte)
        position += 1
        continue
      }

      position += 1
      guard position < bytes.count else { return nil }
      switch bytes[position] {
      case 0x22, 0x5C, 0x2F:
        value.append(bytes[position])
      case 0x62:
        value.append(0x08)
      case 0x66:
        value.append(0x0C)
      case 0x6E:
        value.append(0x0A)
      case 0x72:
        value.append(0x0D)
      case 0x74:
        value.append(0x09)
      case 0x75:
        guard position + 4 < bytes.count else { return nil }
        var code: UInt16 = 0
        for offset in 1...4 {
          guard let nibble = hexValue(bytes[position + offset]) else {
            return nil
          }
          code = (code << 4) | UInt16(nibble)
        }
        // Product field names are ASCII. Match the Windows parser's
        // treatment of escaped non-ASCII keys while still validating syntax.
        value.append(code <= 0x7F ? UInt8(code) : 0x3F)
        position += 4
      default:
        return nil
      }
      position += 1
    }
    return nil
  }

  private static func skipValue(
    _ bytes: [UInt8],
    from start: Int
  ) -> Int? {
    guard start < bytes.count else { return nil }
    if bytes[start] == Character("\"").asciiValue {
      return parseString(bytes, from: start)?.end
    }
    if bytes[start] == Character("{").asciiValue ||
        bytes[start] == Character("[").asciiValue {
      var containers = [UInt8]()
      var position = start
      while position < bytes.count {
        let byte = bytes[position]
        if byte == Character("\"").asciiValue {
          guard let stringEnd = parseString(bytes, from: position) else {
            return nil
          }
          position = stringEnd.end
          continue
        }
        if byte == Character("{").asciiValue ||
            byte == Character("[").asciiValue {
          containers.append(byte)
          position += 1
          continue
        }
        if byte == Character("}").asciiValue ||
            byte == Character("]").asciiValue {
          guard let opening = containers.last,
                (byte == Character("}").asciiValue &&
                  opening == Character("{").asciiValue) ||
                (byte == Character("]").asciiValue &&
                  opening == Character("[").asciiValue)
          else {
            return nil
          }
          containers.removeLast()
          position += 1
          if containers.isEmpty { return position }
          continue
        }
        position += 1
      }
      return nil
    }

    var position = start
    while position < bytes.count {
      let byte = bytes[position]
      if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D ||
          byte == Character(",").asciiValue ||
          byte == Character("}").asciiValue ||
          byte == Character("]").asciiValue {
        break
      }
      position += 1
    }
    return position == start ? nil : position
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

private struct MutationPlan {
  let operation: String
  let name: String
  let mutations: [FileMutation]
}

private enum BackupState {
  case missing
  case data(Data)
}
