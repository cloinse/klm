import CryptoKit
import Darwin
import Foundation

private let maximumRequestSize = 2_500_000

private enum OneShotHelperError: LocalizedError {
  case invalidArguments
  case administratorRequired
  case requestFileUnavailable(String)
  case requestFileIsNotRegular
  case requestFilePermissions(UInt16)
  case requestFileOutsideTemporaryDirectory(String)
  case requestTooLarge
  case digestMismatch

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "Expected --request <path> --sha256 <digest>."
    case .administratorRequired:
      return "The helper must be run with administrator authorization."
    case .requestFileUnavailable(let reason):
      return "The private request file is unavailable: \(reason)"
    case .requestFileIsNotRegular:
      return "The private request path is not a regular file."
    case .requestFilePermissions(let permissions):
      return String(
        format: "The request file permissions are unsafe: %03o.",
        permissions
      )
    case .requestFileOutsideTemporaryDirectory(let path):
      return "The request file is outside an approved temporary directory: \(path)"
    case .requestTooLarge:
      return "The mutation request is too large."
    case .digestMismatch:
      return "The mutation request changed after authorization was requested."
    }
  }
}

private func argumentValue(_ name: String) -> String? {
  guard let index = CommandLine.arguments.firstIndex(of: name),
        CommandLine.arguments.indices.contains(index + 1)
  else {
    return nil
  }
  return CommandLine.arguments[index + 1]
}

private func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func securelyMatches(_ lhs: String, _ rhs: String) -> Bool {
  let left = Array(lhs.lowercased().utf8)
  let right = Array(rhs.lowercased().utf8)
  guard left.count == right.count else { return false }

  var difference: UInt8 = 0
  for index in left.indices {
    difference |= left[index] ^ right[index]
  }
  return difference == 0
}

private func readValidatedRequest(at path: String) throws -> Data {
  guard path.hasPrefix("/") else {
    throw OneShotHelperError.requestFileOutsideTemporaryDirectory(path)
  }

  var fileInfo = stat()
  guard lstat(path, &fileInfo) == 0 else {
    throw OneShotHelperError.requestFileUnavailable(
      String(cString: strerror(errno))
    )
  }
  guard (fileInfo.st_mode & S_IFMT) == S_IFREG else {
    throw OneShotHelperError.requestFileIsNotRegular
  }
  let publicPermissions = UInt16(fileInfo.st_mode & 0o077)
  guard publicPermissions == 0 else {
    throw OneShotHelperError.requestFilePermissions(publicPermissions)
  }

  let canonicalPath = URL(fileURLWithPath: path)
    .resolvingSymlinksInPath()
    .standardizedFileURL.path
  // Foundation may expose the same system temporary roots with or without
  // their /private prefix, depending on which compatibility symlink was used.
  guard canonicalPath.hasPrefix("/var/folders/") ||
          canonicalPath.hasPrefix("/private/var/folders/") ||
          canonicalPath.hasPrefix("/tmp/") ||
          canonicalPath.hasPrefix("/private/tmp/")
  else {
    throw OneShotHelperError.requestFileOutsideTemporaryDirectory(canonicalPath)
  }

  guard fileInfo.st_size >= 0, fileInfo.st_size <= maximumRequestSize else {
    throw OneShotHelperError.requestTooLarge
  }
  let data = try Data(contentsOf: URL(fileURLWithPath: canonicalPath), options: .mappedIfSafe)
  guard data.count <= maximumRequestSize else {
    throw OneShotHelperError.requestTooLarge
  }
  return data
}

private func writeStandardError(_ message: String) {
  guard let data = "Kontakt Library Manager: \(message)\n".data(using: .utf8) else {
    return
  }
  FileHandle.standardError.write(data)
}

do {
  guard geteuid() == 0 else {
    throw OneShotHelperError.administratorRequired
  }
  guard let requestPath = argumentValue("--request"),
        let expectedDigest = argumentValue("--sha256"),
        expectedDigest.count == 64,
        expectedDigest.allSatisfy({ $0.isHexDigit })
  else {
    throw OneShotHelperError.invalidArguments
  }

  let requestData = try readValidatedRequest(at: requestPath)
  guard securelyMatches(sha256Hex(requestData), expectedDigest) else {
    throw OneShotHelperError.digestMismatch
  }

  let response = try MutationTransaction.execute(requestData: requestData)
  let responseData = try JSONSerialization.data(withJSONObject: response)
  FileHandle.standardOutput.write(responseData)
  FileHandle.standardOutput.write(Data([0x0A]))
} catch {
  writeStandardError(error.localizedDescription)
  exit(EXIT_FAILURE)
}
