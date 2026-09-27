#include "shell_bridge.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <cwctype>
#include <string>

namespace {

constexpr char kChannelName[] =
    "com.juanayala.kontaktLibraryManager/windows_shell";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty() || utf8.size() > 32767) return {};
  const int input_length = static_cast<int>(utf8.size());
  const int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), input_length, nullptr, 0);
  if (target_length <= 0) return {};
  std::wstring utf16(static_cast<size_t>(target_length), L'\0');
  const int converted_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), input_length, utf16.data(),
      target_length);
  if (converted_length <= 0) return {};
  return utf16;
}

std::wstring NormalizeExplorerPath(std::wstring path) {
  for (wchar_t& character : path) {
    if (character == L'/') character = L'\\';
  }
  while (!path.empty() &&
         std::iswspace(static_cast<wint_t>(path.front())) != 0) {
    path.erase(path.begin());
  }
  while (!path.empty() &&
         (std::iswspace(static_cast<wint_t>(path.back())) != 0 ||
          path.back() == L'\\')) {
    if (path.size() <= 3 && path.back() == L'\\') break;
    path.pop_back();
  }
  return path;
}

const char* OpenLibraryFolder(const std::wstring& path) {
  if (path.empty()) return "invalid_path";
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = ::GetLastError();
    if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
      return "path_not_found";
    }
    return "explorer_failed";
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) return "path_not_found";

  // explore opens this folder. Selecting it would leave Explorer in the parent.
  SHELLEXECUTEINFOW execute{};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_FLAG_NO_UI;
  execute.lpVerb = L"explore";
  execute.lpFile = path.c_str();
  execute.nShow = SW_SHOWNORMAL;
  if (!::ShellExecuteExW(&execute)) return "explorer_failed";
  return nullptr;
}

}  // namespace

ShellBridge::ShellBridge(flutter::BinaryMessenger* messenger)
    : channel_(
          std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              messenger, kChannelName,
              &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

ShellBridge::~ShellBridge() { channel_->SetMethodCallHandler(nullptr); }

void ShellBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "revealInExplorer") {
    result->NotImplemented();
    return;
  }
  const auto* arguments = call.arguments();
  const auto* utf8_path =
      arguments == nullptr ? nullptr : std::get_if<std::string>(arguments);
  if (utf8_path == nullptr) {
    result->Error("invalid_path", "The Explorer path is invalid.");
    return;
  }
  const std::wstring path = NormalizeExplorerPath(Utf16FromUtf8(*utf8_path));
  const char* error_code = OpenLibraryFolder(path);
  if (error_code != nullptr) {
    result->Error(error_code, "Explorer could not show the library folder.");
    return;
  }
  result->Success();
}
