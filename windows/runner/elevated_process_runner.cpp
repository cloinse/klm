#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

#include "native_mutation.h"

namespace {

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
  }
  ::LocalFree(arguments);
  return exit_code;
}
