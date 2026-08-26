import Foundation

let manager = FileManager.default
let temporaryPath = manager.temporaryDirectory.standardizedFileURL.path
let canonicalTemporaryPath = temporaryPath.hasPrefix("/var/")
  ? "/private\(temporaryPath)"
  : temporaryPath
let root = URL(fileURLWithPath: canonicalTemporaryPath, isDirectory: true)
  .appendingPathComponent(
    "kontakt-helper-smoke-\(UUID().uuidString)",
    isDirectory: true
  )
defer { try? manager.removeItem(at: root) }

let locations = MutationLocations(
  serviceCenter: root.appendingPathComponent("Service Center", isDirectory: true),
  preferences: root.appendingPathComponent("Preferences", isDirectory: true),
  installedProducts: root.appendingPathComponent("installed_products", isDirectory: true)
)
let sampleDirectory = root.appendingPathComponent("Samples", isDirectory: true)
let originalContent = root.appendingPathComponent(
  "Original Content",
  isDirectory: true
)
let relocatedContent = root.appendingPathComponent(
  "Relocated Content",
  isDirectory: true
)

for directory in [
  locations.serviceCenter,
  locations.preferences,
  locations.installedProducts,
  sampleDirectory,
  originalContent,
  relocatedContent,
] {
  try manager.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
}

let preservedName = "Preserved Library"
let preservedRegKey = "PreservedLibrary"
let preservedSNPID = "P01"
let preservedServiceURL = locations.serviceCenter.appendingPathComponent(
  "\(preservedName).xml"
)
let preservedPlistURL = locations.preferences.appendingPathComponent(
  "com.native-instruments.\(preservedRegKey).plist"
)
let preservedJSONURL = locations.installedProducts.appendingPathComponent(
  "\(preservedName).json"
)
let preservedXML = """
<ProductHints><Product>
  <Name>\(preservedName)</Name><RegKey>\(preservedRegKey)</RegKey><SNPID>\(preservedSNPID)</SNPID>
  <Type>Content</Type><Company>Original Vendor Metadata</Company>
</Product></ProductHints>
"""
let preservedXMLData = Data(preservedXML.utf8)
try preservedXMLData.write(to: preservedServiceURL)

let preservedPlist: [String: Any] = [
  "ContentDir": originalContent.path,
  "RegKey": preservedRegKey,
  "SNPID": preservedSNPID,
  "Name": preservedName,
  "Visibility": 3,
  "NativeAccessField": "keep-plist-value",
]
let preservedPlistData = try PropertyListSerialization.data(
  fromPropertyList: preservedPlist,
  format: .xml,
  options: 0
)
try preservedPlistData.write(to: preservedPlistURL)

let preservedJSONText = """
{"ContentDir":"\(originalContent.path)","InstallSource":"Native Access","Nested":{"keep":true}}
"""
let preservedJSONData = Data(preservedJSONText.utf8)
try preservedJSONData.write(to: preservedJSONURL)

let replacementXML = """
<ProductHints><Product><Name>\(preservedName)</Name><RegKey>\(preservedRegKey)</RegKey><SNPID>\(preservedSNPID)</SNPID><Type>Content</Type><Company>Replacement Metadata</Company></Product></ProductHints>
"""
let upsertRequest: [String: Any] = [
  "version": 1,
  "operation": "upsert",
  "name": preservedName,
  "regKey": preservedRegKey,
  "snpid": preservedSNPID,
  "contentPath": originalContent.path,
  "productHintsXml": replacementXML,
  "visibility": 3,
]
let upsertResponse = try MutationTransaction.execute(
  requestData: JSONSerialization.data(withJSONObject: upsertRequest),
  locations: locations
)

precondition((upsertResponse["operation"] as? String) == "upsert")
let serviceDataAfterUpsert = try Data(contentsOf: preservedServiceURL)
let plistDataAfterUpsert = try Data(contentsOf: preservedPlistURL)
let jsonDataAfterUpsert = try Data(contentsOf: preservedJSONURL)
precondition(serviceDataAfterUpsert == preservedXMLData)
precondition(plistDataAfterUpsert == preservedPlistData)
precondition(jsonDataAfterUpsert == preservedJSONData)

let relocateRequest: [String: Any] = [
  "version": 1,
  "operation": "relocate",
  "name": preservedName,
  "regKey": preservedRegKey,
  "snpid": preservedSNPID,
  "contentPath": relocatedContent.path,
]
_ = try MutationTransaction.execute(
  requestData: JSONSerialization.data(withJSONObject: relocateRequest),
  locations: locations
)

let relocatedJSONData = try Data(contentsOf: preservedJSONURL)
let relocatedJSON = try JSONSerialization.jsonObject(with: relocatedJSONData)
  as! [String: Any]
precondition(relocatedJSON["ContentDir"] as? String == relocatedContent.path)
precondition(relocatedJSON["InstallSource"] as? String == "Native Access")
precondition(
  (relocatedJSON["Nested"] as? [String: Any])?["keep"] as? Bool == true
)
let relocatedJSONText = String(data: relocatedJSONData, encoding: .utf8)!
precondition(!relocatedJSONText.contains("\\/"))

let relocatedPlistData = try Data(contentsOf: preservedPlistURL)
let relocatedPlist = try PropertyListSerialization.propertyList(
  from: relocatedPlistData,
  options: [],
  format: nil
) as! [String: Any]
precondition(relocatedPlist["ContentDir"] as? String == relocatedContent.path)
precondition(
  relocatedPlist["NativeAccessField"] as? String == "keep-plist-value"
)
let serviceDataAfterRelocate = try Data(contentsOf: preservedServiceURL)
precondition(serviceDataAfterRelocate == preservedXMLData)

// The duplicate RegKey reproduces a damaged classic order. Batch removal must
// delete the shared preference once without rejecting the whole transaction.
let records = ["Test Library": "TestLibrary", "Second Library": "TestLibrary"]
  .flatMap { name, regKey in
    [
      locations.serviceCenter.appendingPathComponent("\(name).xml"),
      locations.preferences.appendingPathComponent(
        "com.native-instruments.\(regKey).plist"
      ),
      locations.installedProducts.appendingPathComponent("\(name).json"),
    ]
  }
for record in records {
  try Data("test record".utf8).write(to: record)
}
try Data("sample data".utf8).write(
  to: sampleDirectory.appendingPathComponent("instrument.nki")
)

let request: [String: Any] = [
  "version": 1,
  "operations": [
    [
      "version": 1,
      "operation": "remove",
      "name": "Test Library",
      "regKey": "TestLibrary",
    ],
    [
      "version": 1,
      "operation": "remove",
      "name": "Second Library",
      "regKey": "TestLibrary",
    ],
  ],
]
let requestData = try JSONSerialization.data(withJSONObject: request)
let response = try MutationTransaction.execute(
  requestData: requestData,
  locations: locations
)

precondition(records.allSatisfy { !manager.fileExists(atPath: $0.path) })
precondition(manager.fileExists(atPath: sampleDirectory.path))
precondition((response["operation"] as? String) == "batch")
precondition((response["results"] as? [[String: Any]])?.count == 2)

print("Native helper preservation and batch removal smoke tests passed.")
