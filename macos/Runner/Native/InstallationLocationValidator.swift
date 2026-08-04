import Foundation

enum InstallationLocationValidator {
  private static let applicationsDirectory = URL(
    fileURLWithPath: "/Applications",
    isDirectory: true
  ).resolvingSymlinksInPath().standardizedFileURL

  static var isCurrentLocationAllowed: Bool {
#if DEBUG
    return true
#else
    return isAllowed(bundleURL: Bundle.main.bundleURL)
#endif
  }

  static func isAllowed(bundleURL: URL) -> Bool {
    let resolvedBundleURL = bundleURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let applicationsPath = applicationsDirectory.path + "/"
    return resolvedBundleURL.path.hasPrefix(applicationsPath)
  }
}
