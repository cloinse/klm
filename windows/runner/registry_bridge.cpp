#include "registry_bridge.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cwctype>
#include <iterator>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "utils.h"

namespace {

constexpr char kChannelName[] =
    "com.juanayala.kontaktLibraryManager/windows_registry";
constexpr wchar_t kNativeInstrumentsKey[] =
    L"SOFTWARE\\Native Instruments";
constexpr const wchar_t* kKontaktApplicationKeys[] = {
    L"Kontakt", L"Kontakt 5", L"Kontakt 6", L"Kontakt 7", L"Kontakt 8"};

class ScopedRegistryKey {
 public:
  ScopedRegistryKey() = default;
  explicit ScopedRegistryKey(HKEY key) : key_(key) {}
  ~ScopedRegistryKey() {
    if (key_ != nullptr) ::RegCloseKey(key_);
  }

  ScopedRegistryKey(const ScopedRegistryKey&) = delete;
  ScopedRegistryKey& operator=(const ScopedRegistryKey&) = delete;

  ScopedRegistryKey(ScopedRegistryKey&& other) noexcept : key_(other.key_) {
    other.key_ = nullptr;
  }

  ScopedRegistryKey& operator=(ScopedRegistryKey&& other) noexcept {
    if (this == &other) return *this;
    if (key_ != nullptr) ::RegCloseKey(key_);
    key_ = other.key_;
    other.key_ = nullptr;
    return *this;
  }

  HKEY get() const { return key_; }
  explicit operator bool() const { return key_ != nullptr; }

 private:
  HKEY key_ = nullptr;
};

std::wstring Trim(std::wstring value) {
  const auto first = std::find_if_not(value.begin(), value.end(), [](wchar_t c) {
    return std::iswspace(c) != 0;
  });
  const auto last = std::find_if_not(value.rbegin(), value.rend(), [](wchar_t c) {
                      return std::iswspace(c) != 0;
                    }).base();
  if (first >= last) return {};
  return std::wstring(first, last);
}

std::wstring Normalize(const std::wstring& value) {
  std::wstring normalized = Trim(value);
  std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return normalized;
}

ScopedRegistryKey OpenKey(HKEY parent, const std::wstring& path,
                          REGSAM access = KEY_READ) {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(parent, path.c_str(), 0, access, &key) != ERROR_SUCCESS) {
    return {};
  }
  return ScopedRegistryKey(key);
}

std::optional<std::wstring> ReadString(HKEY key, const wchar_t* name) {
  DWORD type = 0;
  DWORD byte_count = 0;
  constexpr DWORD flags =
      RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND;
  LONG status =
      ::RegGetValueW(key, nullptr, name, flags, &type, nullptr, &byte_count);
  if (status != ERROR_SUCCESS || byte_count == 0) return std::nullopt;

  std::vector<wchar_t> buffer(byte_count / sizeof(wchar_t) + 1, L'\0');
  status = ::RegGetValueW(key, nullptr, name, flags, &type, buffer.data(),
                          &byte_count);
  if (status != ERROR_SUCCESS) return std::nullopt;
  return Trim(std::wstring(buffer.data()));
}

std::optional<std::int64_t> ReadInteger(HKEY key, const wchar_t* name) {
  DWORD type = 0;
  DWORD byte_count = 0;
  LONG status = ::RegQueryValueExW(key, name, nullptr, &type, nullptr,
                                   &byte_count);
  if (status != ERROR_SUCCESS || byte_count == 0) return std::nullopt;

  std::vector<BYTE> buffer(byte_count + sizeof(wchar_t), 0);
  status = ::RegQueryValueExW(key, name, nullptr, &type, buffer.data(),
                              &byte_count);
  if (status != ERROR_SUCCESS) return std::nullopt;

  if (type == REG_DWORD && byte_count >= sizeof(DWORD)) {
    DWORD value = 0;
    std::memcpy(&value, buffer.data(), sizeof(value));
    return static_cast<std::int64_t>(value);
  }
  if (type == REG_QWORD && byte_count >= sizeof(ULONGLONG)) {
    ULONGLONG value = 0;
    std::memcpy(&value, buffer.data(), sizeof(value));
    return static_cast<std::int64_t>(value);
  }
  if (type != REG_SZ && type != REG_EXPAND_SZ) return std::nullopt;

  const std::wstring text =
      Trim(std::wstring(reinterpret_cast<const wchar_t*>(buffer.data())));
  if (text.empty()) return std::nullopt;
  wchar_t* end = nullptr;
  const long long value = std::wcstoll(text.c_str(), &end, 10);
  if (end == text.c_str() || end == nullptr || *end != L'\0') {
    return std::nullopt;
  }
  return static_cast<std::int64_t>(value);
}

std::vector<std::wstring> SubKeyNames(HKEY key) {
  DWORD subkey_count = 0;
  DWORD max_name_length = 0;
  if (::RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &subkey_count,
                         &max_name_length, nullptr, nullptr, nullptr, nullptr,
                         nullptr, nullptr) != ERROR_SUCCESS) {
    return {};
  }

  std::vector<std::wstring> names;
  names.reserve(subkey_count);
  std::vector<wchar_t> buffer(max_name_length + 1, L'\0');
  for (DWORD index = 0; index < subkey_count; ++index) {
    DWORD length = static_cast<DWORD>(buffer.size());
    const LONG status = ::RegEnumKeyExW(key, index, buffer.data(), &length,
                                        nullptr, nullptr, nullptr, nullptr);
    if (status == ERROR_SUCCESS) names.emplace_back(buffer.data(), length);
  }
  return names;
}

using UserListIndexes = std::unordered_map<std::wstring, std::int64_t>;

void AddUserListIndexes(REGSAM view, UserListIndexes* indexes) {
  ScopedRegistryKey root =
      OpenKey(HKEY_CURRENT_USER, kNativeInstrumentsKey, KEY_READ | view);
  if (!root) return;

  for (const std::wstring& subkey_name : SubKeyNames(root.get())) {
    ScopedRegistryKey product = OpenKey(root.get(), subkey_name);
    if (!product) continue;
    const std::optional<std::int64_t> index =
        ReadInteger(product.get(), L"UserListIndex");
    if (!index.has_value()) continue;

    const std::wstring identity = Normalize(subkey_name);
    if (!identity.empty()) indexes->emplace(identity, *index);
    const std::wstring reg_key =
        Normalize(ReadString(product.get(), L"RegKey").value_or(L""));
    if (!reg_key.empty()) indexes->emplace(reg_key, *index);
  }
}

std::optional<std::int64_t> FindUserListIndex(
    const UserListIndexes& indexes, const std::wstring& reg_key,
    const std::wstring& subkey_name) {
  for (const std::wstring& candidate : {reg_key, subkey_name}) {
    const auto iterator = indexes.find(Normalize(candidate));
    if (iterator != indexes.end()) return iterator->second;
  }
  return std::nullopt;
}

void SetString(flutter::EncodableMap* record, const char* name,
               const std::wstring& value) {
  (*record)[flutter::EncodableValue(name)] =
      flutter::EncodableValue(Utf8FromUtf16(value.c_str()));
}

std::optional<std::wstring> Utf16FromUtf8(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int required = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (required <= 0) return std::nullopt;
  std::wstring converted(static_cast<size_t>(required), L'\0');
  const int written = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), converted.data(), required);
  if (written != required) return std::nullopt;
  return converted;
}

const flutter::EncodableValue* MapValue(const flutter::EncodableMap& map,
                                        const char* name) {
  const auto iterator = map.find(flutter::EncodableValue(name));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::optional<std::wstring> MapString(const flutter::EncodableMap& map,
                                      const char* name) {
  const flutter::EncodableValue* value = MapValue(map, name);
  if (value == nullptr) return std::nullopt;
  const std::string* text = std::get_if<std::string>(value);
  return text == nullptr ? std::nullopt : Utf16FromUtf8(*text);
}

std::optional<std::int64_t> MapInteger(const flutter::EncodableMap& map,
                                       const char* name) {
  const flutter::EncodableValue* value = MapValue(map, name);
  if (value == nullptr) return std::nullopt;
  if (const auto* integer = std::get_if<std::int32_t>(value)) return *integer;
  if (const auto* integer = std::get_if<std::int64_t>(value)) return *integer;
  return std::nullopt;
}

bool IsSafeRegistryComponent(const std::wstring& value) {
  if (value.empty() || value.size() > 255 || value == L"." || value == L".." ||
      value.back() == L'.' || value.back() == L' ') {
    return false;
  }
  return value.find_first_of(L"/\\\r\n") == std::wstring::npos;
}

bool IsKontaktProcessName(std::wstring name) {
  constexpr wchar_t kExecutableSuffix[] = L".exe";
  if (name.size() >= 4 &&
      ::CompareStringOrdinal(name.data() + name.size() - 4, 4,
                             kExecutableSuffix, 4, TRUE) == CSTR_EQUAL) {
    name.resize(name.size() - 4);
  }
  name = Normalize(name);
  constexpr wchar_t kPrefix[] = L"kontakt";
  if (name == kPrefix) return true;
  if (name.size() <= 8 || name.compare(0, 8, L"kontakt ") != 0) return false;

  bool needs_digit = true;
  for (size_t index = 8; index < name.size(); ++index) {
    const wchar_t character = name[index];
    if (character >= L'0' && character <= L'9') {
      needs_digit = false;
    } else if (character == L'.' && !needs_digit) {
      needs_digit = true;
    } else {
      return false;
    }
  }
  return !needs_digit;
}

bool IsKontaktRunning() {
  const HANDLE snapshot = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return false;
  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  bool running = false;
  if (::Process32FirstW(snapshot, &entry)) {
    do {
      if (IsKontaktProcessName(entry.szExeFile)) {
        running = true;
        break;
      }
    } while (::Process32NextW(snapshot, &entry));
  }
  ::CloseHandle(snapshot);
  return running;
}

struct ClassicOrderEntry {
  std::wstring reg_key;
  std::wstring name;
  std::optional<std::wstring> snpid;
  DWORD index = 0;
};

struct RegistryValueBackup {
  bool existed = false;
  DWORD type = REG_NONE;
  std::vector<BYTE> data;
};

struct RegistryKeyBackup {
  REGSAM view = 0;
  std::wstring path;
  bool existed = false;
  std::map<std::wstring, RegistryValueBackup> values;
};

bool CaptureRegistryBackup(REGSAM view, const std::wstring& path,
                           const std::vector<std::wstring>& value_names,
                           RegistryKeyBackup* backup) {
  backup->view = view;
  backup->path = path;
  HKEY raw_key = nullptr;
  const LONG open_status = ::RegOpenKeyExW(
      HKEY_CURRENT_USER, path.c_str(), 0, KEY_QUERY_VALUE | view, &raw_key);
  if (open_status == ERROR_FILE_NOT_FOUND) {
    for (const auto& name : value_names) backup->values.emplace(name, RegistryValueBackup{});
    return true;
  }
  if (open_status != ERROR_SUCCESS) return false;
  backup->existed = true;
  ScopedRegistryKey key(raw_key);

  for (const std::wstring& name : value_names) {
    RegistryValueBackup value;
    DWORD byte_count = 0;
    LONG status = ::RegQueryValueExW(key.get(), name.c_str(), nullptr,
                                     &value.type, nullptr, &byte_count);
    if (status == ERROR_FILE_NOT_FOUND) {
      backup->values.emplace(name, std::move(value));
      continue;
    }
    if (status != ERROR_SUCCESS) return false;
    value.existed = true;
    value.data.resize(byte_count);
    status = ::RegQueryValueExW(key.get(), name.c_str(), nullptr, &value.type,
                                value.data.data(), &byte_count);
    if (status != ERROR_SUCCESS) return false;
    value.data.resize(byte_count);
    backup->values.emplace(name, std::move(value));
  }
  return true;
}

ScopedRegistryKey CreateUserKey(REGSAM view, const std::wstring& path) {
  HKEY raw_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_READ | KEY_WRITE | view,
                        nullptr, &raw_key, nullptr) != ERROR_SUCCESS) {
    return {};
  }
  return ScopedRegistryKey(raw_key);
}

bool SetRegistryString(HKEY key, const wchar_t* name,
                       const std::wstring& value) {
  const size_t byte_count = (value.size() + 1) * sizeof(wchar_t);
  if (byte_count > MAXDWORD) return false;
  return ::RegSetValueExW(key, name, 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(value.c_str()),
                          static_cast<DWORD>(byte_count)) == ERROR_SUCCESS;
}

bool SetRegistryDword(HKEY key, const wchar_t* name, DWORD value) {
  return ::RegSetValueExW(key, name, 0, REG_DWORD,
                          reinterpret_cast<const BYTE*>(&value),
                          sizeof(value)) == ERROR_SUCCESS;
}

void RestoreRegistryBackup(const RegistryKeyBackup& backup) {
  if (!backup.existed) {
    ::RegDeleteKeyExW(HKEY_CURRENT_USER, backup.path.c_str(), backup.view, 0);
    return;
  }
  ScopedRegistryKey key = CreateUserKey(backup.view, backup.path);
  if (!key) return;
  for (const auto& pair : backup.values) {
    const RegistryValueBackup& value = pair.second;
    if (value.existed) {
      ::RegSetValueExW(key.get(), pair.first.c_str(), 0, value.type,
                       value.data.data(),
                       static_cast<DWORD>(value.data.size()));
    } else {
      ::RegDeleteValueW(key.get(), pair.first.c_str());
    }
  }
}

std::optional<std::vector<ClassicOrderEntry>> DecodeClassicOrder(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) return std::nullopt;
  const auto* encoded_entries =
      std::get_if<flutter::EncodableList>(arguments);
  if (encoded_entries == nullptr || encoded_entries->size() > 10000) {
    return std::nullopt;
  }

  std::vector<ClassicOrderEntry> entries;
  entries.reserve(encoded_entries->size());
  std::unordered_set<std::wstring> reg_keys;
  std::unordered_set<std::int64_t> indexes;
  for (const flutter::EncodableValue& encoded_entry : *encoded_entries) {
    const auto* map = std::get_if<flutter::EncodableMap>(&encoded_entry);
    if (map == nullptr) return std::nullopt;
    const auto reg_key = MapString(*map, "regKey");
    const auto name = MapString(*map, "name");
    const auto index = MapInteger(*map, "userListIndex");
    if (!reg_key.has_value() || !name.has_value() || !index.has_value() ||
        !IsSafeRegistryComponent(*reg_key) ||
        !IsSafeRegistryComponent(*name) || *index < 1 ||
        static_cast<size_t>(*index) > encoded_entries->size()) {
      return std::nullopt;
    }
    const std::wstring identity = Normalize(*reg_key);
    if (!reg_keys.insert(identity).second || !indexes.insert(*index).second) {
      return std::nullopt;
    }
    std::optional<std::wstring> snpid;
    if (MapValue(*map, "snpid") != nullptr) {
      snpid = MapString(*map, "snpid");
      if (!snpid.has_value() || !IsSafeRegistryComponent(*snpid)) {
        return std::nullopt;
      }
    }
    entries.push_back(ClassicOrderEntry{
        *reg_key, *name, std::move(snpid), static_cast<DWORD>(*index)});
  }
  return entries;
}

bool WriteClassicOrder(const std::vector<ClassicOrderEntry>& entries) {
  std::vector<RegistryKeyBackup> backups;
  backups.reserve((entries.size() + std::size(kKontaktApplicationKeys)) * 2);
  bool success = true;

  for (const REGSAM view : {KEY_WOW64_64KEY, KEY_WOW64_32KEY}) {
    for (const ClassicOrderEntry& entry : entries) {
      const std::wstring path =
          std::wstring(kNativeInstrumentsKey) + L"\\" + entry.reg_key;
      RegistryKeyBackup backup;
      if (!CaptureRegistryBackup(
              view, path, {L"UserListIndex", L"Name", L"RegKey", L"SNPID"},
              &backup)) {
        success = false;
        break;
      }
      backups.emplace_back(std::move(backup));
      ScopedRegistryKey key = CreateUserKey(view, path);
      if (!key || !SetRegistryDword(key.get(), L"UserListIndex", entry.index) ||
          !SetRegistryString(key.get(), L"Name", entry.name) ||
          !SetRegistryString(key.get(), L"RegKey", entry.reg_key) ||
          (entry.snpid.has_value() &&
           !SetRegistryString(key.get(), L"SNPID", *entry.snpid))) {
        success = false;
        break;
      }
      const auto saved_index = ReadInteger(key.get(), L"UserListIndex");
      if (!saved_index.has_value() || *saved_index != entry.index) {
        success = false;
        break;
      }
    }
    if (!success) break;

    for (const wchar_t* application_key : kKontaktApplicationKeys) {
      const std::wstring path =
          std::wstring(kNativeInstrumentsKey) + L"\\" + application_key;
      RegistryKeyBackup backup;
      if (!CaptureRegistryBackup(view, path, {L"browserLibsAZSort"},
                                 &backup)) {
        success = false;
        break;
      }
      backups.emplace_back(std::move(backup));
      ScopedRegistryKey key = CreateUserKey(view, path);
      if (!key || !SetRegistryDword(key.get(), L"browserLibsAZSort", 0)) {
        success = false;
        break;
      }
    }
    if (!success) break;
  }

  if (!success) {
    for (auto iterator = backups.rbegin(); iterator != backups.rend();
         ++iterator) {
      RestoreRegistryBackup(*iterator);
    }
  }
  return success;
}

std::optional<flutter::EncodableList> ReadRegistryInventory(
    std::string* error_code, std::string* error_message) {
  UserListIndexes user_list_indexes;
  AddUserListIndexes(KEY_WOW64_64KEY, &user_list_indexes);
  AddUserListIndexes(KEY_WOW64_32KEY, &user_list_indexes);

  flutter::EncodableList records;
  std::unordered_set<std::wstring> seen;
  bool access_denied = false;
  for (const REGSAM view : {KEY_WOW64_64KEY, KEY_WOW64_32KEY}) {
    HKEY raw_root = nullptr;
    const LONG root_status = ::RegOpenKeyExW(
        HKEY_LOCAL_MACHINE, kNativeInstrumentsKey, 0, KEY_READ | view,
        &raw_root);
    if (root_status == ERROR_FILE_NOT_FOUND) continue;
    if (root_status == ERROR_ACCESS_DENIED) {
      access_denied = true;
      continue;
    }
    if (root_status != ERROR_SUCCESS) {
      *error_code = "registry_read_failed";
      *error_message = "Native Instruments Registry access failed (Win32 " +
                       std::to_string(root_status) + ").";
      return std::nullopt;
    }
    ScopedRegistryKey root(raw_root);

    for (const std::wstring& subkey_name : SubKeyNames(root.get())) {
      const std::wstring identity = Normalize(subkey_name);
      if (identity.empty() || seen.find(identity) != seen.end()) continue;

      ScopedRegistryKey product = OpenKey(root.get(), subkey_name);
      if (!product) continue;
      std::wstring reg_key =
          ReadString(product.get(), L"RegKey").value_or(subkey_name);
      if (Trim(reg_key).empty()) reg_key = subkey_name;
      const std::wstring name =
          ReadString(product.get(), L"Name").value_or(reg_key);

      flutter::EncodableMap record;
      SetString(&record, "name", name);
      SetString(&record, "regKey", reg_key);
      const std::optional<std::wstring> snpid =
          ReadString(product.get(), L"SNPID");
      if (snpid.has_value() && !snpid->empty()) {
        SetString(&record, "snpid", *snpid);
      }
      const std::optional<std::wstring> content_path =
          ReadString(product.get(), L"ContentDir");
      if (content_path.has_value() && !content_path->empty()) {
        SetString(&record, "contentPath", *content_path);
      }
      const std::optional<std::int64_t> visibility =
          ReadInteger(product.get(), L"Visibility");
      if (visibility.has_value()) {
        record[flutter::EncodableValue("visibility")] =
            flutter::EncodableValue(*visibility);
      }
      std::optional<std::int64_t> user_list_index = FindUserListIndex(
          user_list_indexes, reg_key, subkey_name);
      if (!user_list_index.has_value()) {
        user_list_index = ReadInteger(product.get(), L"UserListIndex");
      }
      if (user_list_index.has_value()) {
        record[flutter::EncodableValue("userListIndex")] =
            flutter::EncodableValue(*user_list_index);
      }

      records.emplace_back(std::move(record));
      seen.insert(identity);
    }
  }
  if (records.empty() && access_denied) {
    *error_code = "registry_access_denied";
    *error_message =
        "Windows denied access to the Native Instruments Registry.";
    return std::nullopt;
  }
  return records;
}

}  // namespace

RegistryBridge::RegistryBridge(flutter::BinaryMessenger* messenger)
    : channel_(
          std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              messenger, kChannelName,
              &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

RegistryBridge::~RegistryBridge() {
  channel_->SetMethodCallHandler(nullptr);
}

void RegistryBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "writeClassicOrder") {
    if (IsKontaktRunning()) {
      result->Error(
          "kontakt_running",
          "Close Kontakt and any DAW using Kontakt before saving the classic "
          "library order.");
      return;
    }
    const auto entries = DecodeClassicOrder(call.arguments());
    if (!entries.has_value()) {
      result->Error("classic_order_write_failed",
                    "The classic Kontakt order is invalid.");
      return;
    }
    if (!WriteClassicOrder(*entries)) {
      result->Error("classic_order_write_failed",
                    "The classic Kontakt order could not be saved.");
      return;
    }
    result->Success();
    return;
  }
  if (call.method_name() != "readInventory") {
    result->NotImplemented();
    return;
  }
  std::string error_code;
  std::string error_message;
  const auto records = ReadRegistryInventory(&error_code, &error_message);
  if (!records.has_value()) {
    result->Error(error_code.c_str(), error_message.c_str());
    return;
  }
  result->Success(flutter::EncodableValue(*records));
}
