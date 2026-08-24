#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

#include "native_mutation.h"

namespace {

constexpr wchar_t kHelperFileName[] = L"KontaktLibraryHelper.ps1";

std::wstring ExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return {};
    if (length < buffer.size() - 1) {
      std::wstring path(buffer.data(), length);
      const size_t separator = path.find_last_of(L"\\/");
      if (separator == std::wstring::npos) return {};
      path.resize(separator);
      return path;
    }
    if (buffer.size() >= 32768) return {};
    buffer.resize(buffer.size() * 2, L'\0');
  }
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return {};
    if (static_cast<size_t>(length) < buffer.size() - 1) {
      return std::wstring(buffer.data(), length);
    }
    if (buffer.size() >= 32768) return {};
    buffer.resize(buffer.size() * 2, L'\0');
  }
}

std::wstring FullPath(const std::wstring& value) {
  DWORD required = ::GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
  if (required == 0) return {};
  std::vector<wchar_t> buffer(required, L'\0');
  const DWORD length = ::GetFullPathNameW(
      value.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
  if (length == 0 || length >= buffer.size()) return {};
  return std::wstring(buffer.data(), length);
}

bool SamePath(const std::wstring& left, const std::wstring& right) {
  const std::wstring normalized_left = FullPath(left);
  const std::wstring normalized_right = FullPath(right);
  return !normalized_left.empty() && !normalized_right.empty() &&
         ::CompareStringOrdinal(normalized_left.c_str(), -1,
                                normalized_right.c_str(), -1, TRUE) ==
             CSTR_EQUAL;
}

bool IsSha256(const std::wstring& value) {
  return value.size() == 64 &&
         std::all_of(value.begin(), value.end(), [](wchar_t character) {
           return (character >= L'0' && character <= L'9') ||
                  (character >= L'a' && character <= L'f') ||
                  (character >= L'A' && character <= L'F');
         });
}

bool IsSafeArgument(const std::wstring& value) {
  return !value.empty() && value.find(L'"') == std::wstring::npos &&
         value.find(L'\r') == std::wstring::npos &&
         value.find(L'\n') == std::wstring::npos;
}

std::wstring Quote(const std::wstring& value) {
  return L"\"" + value + L"\"";
}

std::wstring PowerShellPath() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  const UINT length =
      ::GetSystemDirectoryW(buffer.data(), static_cast<UINT>(buffer.size()));
  if (length == 0 || length >= buffer.size()) return {};
  return std::wstring(buffer.data(), length) +
         L"\\WindowsPowerShell\\v1.0\\powershell.exe";
}

int RunElevatedMutation(const std::wstring& helper_path,
                        const std::wstring& request_path,
                        const std::wstring& request_sha256,
                        const std::wstring& response_path) {
  const std::wstring directory = ExecutableDirectory();
  if (directory.empty()) return ERROR_BAD_PATHNAME;
  const std::wstring expected_helper = directory + L"\\" + kHelperFileName;
  if (!SamePath(helper_path, expected_helper)) return ERROR_ACCESS_DENIED;

  const DWORD helper_attributes = ::GetFileAttributesW(helper_path.c_str());
  if (helper_attributes == INVALID_FILE_ATTRIBUTES ||
      (helper_attributes & (FILE_ATTRIBUTE_DIRECTORY |
                            FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return ERROR_FILE_NOT_FOUND;
  }
  if (!IsSafeArgument(helper_path) || !IsSafeArgument(request_path) ||
      !IsSafeArgument(response_path) || !IsSha256(request_sha256)) {
    return ERROR_INVALID_PARAMETER;
  }

  const std::wstring powershell = PowerShellPath();
  if (powershell.empty()) return ERROR_FILE_NOT_FOUND;
  const std::wstring arguments =
      L"-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden "
      L"-ExecutionPolicy Bypass -File " +
      Quote(helper_path) + L" -Mode mutation -RequestPath " +
      Quote(request_path) + L" -RequestSha256 " + request_sha256 +
      L" -ResponsePath " + Quote(response_path);

  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask =
      SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
  execute_info.lpVerb = L"runas";
  execute_info.lpFile = powershell.c_str();
  execute_info.lpParameters = arguments.c_str();
  execute_info.lpDirectory = directory.c_str();
  execute_info.nShow = SW_HIDE;
  if (!::ShellExecuteExW(&execute_info)) {
    return static_cast<int>(::GetLastError());
  }

  const DWORD wait_result = ::WaitForSingleObject(execute_info.hProcess, INFINITE);
  DWORD exit_code = ERROR_GEN_FAILURE;
  if (wait_result == WAIT_OBJECT_0) {
    ::GetExitCodeProcess(execute_info.hProcess, &exit_code);
  }
  ::CloseHandle(execute_info.hProcess);
  return static_cast<int>(exit_code);
}

bool IsAdministrator() {
  BOOL is_member = FALSE;
  SID_IDENTIFIER_AUTHORITY nt_authority = SECURITY_NT_AUTHORITY;
  PSID administrators = nullptr;
  if (!::AllocateAndInitializeSid(
          &nt_authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
          DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &administrators)) {
    return false;
  }
  const BOOL checked =
      ::CheckTokenMembership(nullptr, administrators, &is_member);
  ::FreeSid(administrators);
  return checked != FALSE && is_member != FALSE;
}

int LaunchNativeMutationElevated(const std::wstring& request_path,
                                 const std::wstring& request_sha256,
                                 const std::wstring& response_path) {
  if (!IsSafeArgument(request_path) || !IsSha256(request_sha256) ||
      !IsSafeArgument(response_path)) {
    return ERROR_INVALID_PARAMETER;
  }
  const std::wstring executable = ExecutablePath();
  const std::wstring directory = ExecutableDirectory();
  if (executable.empty() || directory.empty()) return ERROR_BAD_PATHNAME;
  const std::wstring arguments =
      L"--apply-native-mutation " + Quote(request_path) + L" " +
      request_sha256 + L" " + Quote(response_path);

  SHELLEXECUTEINFOW execute_info = {};
  execute_info.cbSize = sizeof(execute_info);
  execute_info.fMask =
      SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
  execute_info.lpVerb = L"runas";
  execute_info.lpFile = executable.c_str();
  execute_info.lpParameters = arguments.c_str();
  execute_info.lpDirectory = directory.c_str();
  execute_info.nShow = SW_HIDE;
  if (!::ShellExecuteExW(&execute_info)) {
    return static_cast<int>(::GetLastError());
  }

  const DWORD wait_result = ::WaitForSingleObject(execute_info.hProcess, INFINITE);
  DWORD exit_code = ERROR_GEN_FAILURE;
  if (wait_result == WAIT_OBJECT_0) {
    ::GetExitCodeProcess(execute_info.hProcess, &exit_code);
  }
  ::CloseHandle(execute_info.hProcess);
  return static_cast<int>(exit_code);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argument_count = 0;
  wchar_t** arguments = ::CommandLineToArgvW(
      ::GetCommandLineW(), &argument_count);
  if (arguments == nullptr) return ERROR_INVALID_PARAMETER;

  int exit_code = ERROR_INVALID_PARAMETER;
  if (argument_count == 5 &&
      std::wstring(arguments[1]) == L"--native-mutation") {
    exit_code = LaunchNativeMutationElevated(arguments[2], arguments[3],
                                             arguments[4]);
  } else if (argument_count == 5 &&
             std::wstring(arguments[1]) == L"--apply-native-mutation") {
    exit_code = IsAdministrator()
                    ? RunNativeMutation(arguments[2], arguments[3], arguments[4])
                    : ERROR_ACCESS_DENIED;
  } else if (argument_count == 5) {
    exit_code = RunElevatedMutation(arguments[1], arguments[2], arguments[3],
                                    arguments[4]);
  }
  ::LocalFree(arguments);
  return exit_code;
}
