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

for directory in [
  locations.serviceCenter,
  locations.preferences,
  locations.installedProducts,
  sampleDirectory,
] {
  try manager.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
}

let records = [
  locations.serviceCenter.appendingPathComponent("Test Library.xml"),
  locations.preferences.appendingPathComponent(
    "com.native-instruments.TestLibrary.plist"
  ),
  locations.installedProducts.appendingPathComponent("Test Library.json"),
]
for record in records {
  try Data("test record".utf8).write(to: record)
}
try Data("sample data".utf8).write(
  to: sampleDirectory.appendingPathComponent("instrument.nki")
)

let request: [String: Any] = [
  "version": 1,
  "operation": "remove",
  "name": "Test Library",
  "regKey": "TestLibrary",
]
let requestData = try JSONSerialization.data(withJSONObject: request)
let response = try MutationTransaction.execute(
  requestData: requestData,
  locations: locations
)

precondition(records.allSatisfy { !manager.fileExists(atPath: $0.path) })
precondition(manager.fileExists(atPath: sampleDirectory.path))
precondition((response["operation"] as? String) == "remove")
precondition((response["changedPaths"] as? [String])?.count == 3)

print("Native helper removal smoke test passed.")
