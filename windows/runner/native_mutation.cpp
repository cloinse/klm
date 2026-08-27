#include "native_mutation.h"

#include <windows.h>

#include <bcrypt.h>
#include <knownfolders.h>
#include <msxml6.h>
#include <shlobj.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <cwctype>
#include <iterator>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;

constexpr size_t kMaximumRequestBytes = 2500000;
constexpr size_t kMaximumBackupBytes = 64 * 1024 * 1024;
constexpr std::uint32_t kMaximumOperations = 1000;
constexpr std::uint32_t kAbsentStringLength = 0xffffffff;
constexpr std::array<std::uint8_t, 8> kRequestMagic = {
    0x4b, 0x4c, 0x4d, 0x4e, 0x4d, 0x55, 0x54, 0x31};
constexpr wchar_t kNativeInstrumentsKey[] =
    L"SOFTWARE\\Native Instruments";

class ScopedHandle {
 public:
  ScopedHandle() = default;
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}
  ~ScopedHandle() {
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      ::CloseHandle(handle_);
    }
  }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  ScopedHandle(ScopedHandle&& other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
  }

  ScopedHandle& operator=(ScopedHandle&& other) noexcept {
    if (this == &other) return *this;
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
      ::CloseHandle(handle_);
    }
    handle_ = other.handle_;
    other.handle_ = nullptr;
    return *this;
  }

  HANDLE get() const { return handle_; }
  explicit operator bool() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }

 private:
  HANDLE handle_ = nullptr;
};

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

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(std::towlower(c));
  });
  return value;
}

bool EqualsInsensitive(const std::wstring& left, const std::wstring& right) {
  return ::CompareStringOrdinal(left.c_str(), -1, right.c_str(), -1, TRUE) ==
         CSTR_EQUAL;
}

bool StartsWithInsensitive(const std::wstring& value,
                           const std::wstring& prefix) {
  return value.size() >= prefix.size() &&
         ::CompareStringOrdinal(value.c_str(), static_cast<int>(prefix.size()),
                                prefix.c_str(),
                                static_cast<int>(prefix.size()), TRUE) ==
             CSTR_EQUAL;
}

std::optional<std::wstring> Utf16FromUtf8(const std::string& value) {
  if (value.empty()) return std::wstring();
  if (value.size() > static_cast<size_t>(INT_MAX)) return std::nullopt;
  const int input_length = static_cast<int>(value.size());
  const int required = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_length, nullptr, 0);
  if (required <= 0) return std::nullopt;
  std::wstring converted(static_cast<size_t>(required), L'\0');
  const int written = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), input_length,
      converted.data(), required);
  if (written != required || converted.find(L'\0') != std::wstring::npos) {
    return std::nullopt;
  }
  return converted;
}

std::optional<std::string> Utf8FromUtf16(const std::wstring& value) {
  if (value.empty()) return std::string();
  if (value.size() > static_cast<size_t>(INT_MAX)) return std::nullopt;
  const int input_length = static_cast<int>(value.size());
  const int required = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), input_length, nullptr, 0,
      nullptr, nullptr);
  if (required <= 0) return std::nullopt;
  std::string converted(static_cast<size_t>(required), '\0');
  const int written = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), input_length,
      converted.data(), required, nullptr, nullptr);
  if (written != required) return std::nullopt;
  return converted;
}

std::wstring FullPath(const std::wstring& value) {
  const DWORD required = ::GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
  if (required == 0) return {};
  std::vector<wchar_t> buffer(required, L'\0');
  const DWORD length = ::GetFullPathNameW(
      value.c_str(), static_cast<DWORD>(buffer.size()), buffer.data(), nullptr);
  if (length == 0 || static_cast<size_t>(length) >= buffer.size()) return {};
  return std::wstring(buffer.data(), length);
}

std::wstring ParentPath(const std::wstring& value) {
  const size_t separator = value.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : value.substr(0, separator);
}

std::wstring FileName(const std::wstring& value) {
  const size_t separator = value.find_last_of(L"\\/");
  return separator == std::wstring::npos ? value : value.substr(separator + 1);
}

std::wstring JoinPath(const std::wstring& left, const std::wstring& right) {
  if (left.empty()) return right;
  if (left.back() == L'\\' || left.back() == L'/') return left + right;
  return left + L"\\" + right;
}

bool IsSafeTemporaryDirectoryName(const std::wstring& value) {
  if (!StartsWithInsensitive(value, L"klm-mutation-")) return false;
  for (const wchar_t character : value) {
    if (!((character >= L'a' && character <= L'z') ||
          (character >= L'A' && character <= L'Z') ||
          (character >= L'0' && character <= L'9') || character == L'-' ||
          character == L'_')) {
      return false;
    }
  }
  return true;
}

bool PathHasReparsePoint(const std::wstring& input) {
  const std::wstring path = FullPath(input);
  if (path.empty()) return true;
  std::wstring current;
  if (path.size() >= 3 && path[1] == L':' &&
      (path[2] == L'\\' || path[2] == L'/')) {
    current = path.substr(0, 3);
  } else {
    std::vector<wchar_t> root_buffer(MAX_PATH, L'\0');
    if (!::GetVolumePathNameW(path.c_str(), root_buffer.data(),
                              static_cast<DWORD>(root_buffer.size()))) {
      return true;
    }
    current = root_buffer.data();
  }
  size_t position = current.size();
  while (position < path.size()) {
    while (position < path.size() &&
           (path[position] == L'\\' || path[position] == L'/')) {
      ++position;
    }
    if (position >= path.size()) break;
    const size_t separator = path.find_first_of(L"\\/", position);
    const size_t end = separator == std::wstring::npos ? path.size() : separator;
    current = JoinPath(current, path.substr(position, end - position));
    const DWORD attributes = ::GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      return true;
    }
    position = end;
  }
  return false;
}

struct TransportPaths {
  std::wstring request;
  std::wstring response;
};

std::optional<TransportPaths> ValidateTransport(
    const std::wstring& request_path, const std::wstring& response_path) {
  const std::wstring request = FullPath(request_path);
  const std::wstring response = FullPath(response_path);
  if (request.empty() || response.empty() ||
      !EqualsInsensitive(FileName(request), L"request.bin") ||
      !EqualsInsensitive(FileName(response), L"response.json")) {
    return std::nullopt;
  }
  const std::wstring request_parent = ParentPath(request);
  const std::wstring response_parent = ParentPath(response);
  if (!EqualsInsensitive(request_parent, response_parent) ||
      !IsSafeTemporaryDirectoryName(FileName(request_parent))) {
    return std::nullopt;
  }

  std::vector<wchar_t> temporary_buffer(32768, L'\0');
  const DWORD temporary_length = ::GetTempPathW(
      static_cast<DWORD>(temporary_buffer.size()), temporary_buffer.data());
  if (temporary_length == 0 ||
      static_cast<size_t>(temporary_length) >= temporary_buffer.size()) {
    return std::nullopt;
  }
  std::wstring temporary_root = FullPath(temporary_buffer.data());
  if (temporary_root.empty()) return std::nullopt;
  if (temporary_root.back() != L'\\') temporary_root.push_back(L'\\');
  if (!StartsWithInsensitive(request, temporary_root) ||
      !StartsWithInsensitive(response, temporary_root) ||
      PathHasReparsePoint(request_parent)) {
    return std::nullopt;
  }

  const DWORD request_attributes = ::GetFileAttributesW(request.c_str());
  if (request_attributes == INVALID_FILE_ATTRIBUTES ||
      (request_attributes &
       (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return std::nullopt;
  }
  if (::GetFileAttributesW(response.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return std::nullopt;
  }
  return TransportPaths{request, response};
}

bool ReadFileBytes(const std::wstring& path, size_t maximum_size,
                   std::vector<std::uint8_t>* bytes) {
  ScopedHandle file(::CreateFileW(
      path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT |
          FILE_FLAG_SEQUENTIAL_SCAN,
      nullptr));
  if (!file) return false;
  BY_HANDLE_FILE_INFORMATION information = {};
  if (!::GetFileInformationByHandle(file.get(), &information) ||
      (information.dwFileAttributes &
       (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return false;
  }
  LARGE_INTEGER size = {};
  if (!::GetFileSizeEx(file.get(), &size) || size.QuadPart < 0 ||
      static_cast<ULONGLONG>(size.QuadPart) > maximum_size ||
      static_cast<ULONGLONG>(size.QuadPart) > MAXDWORD) {
    return false;
  }
  bytes->resize(static_cast<size_t>(size.QuadPart));
  DWORD bytes_read = 0;
  if (!bytes->empty() &&
      (!::ReadFile(file.get(), bytes->data(),
                   static_cast<DWORD>(bytes->size()), &bytes_read, nullptr) ||
       static_cast<size_t>(bytes_read) != bytes->size())) {
    return false;
  }
  return true;
}

bool ParseSha256(const std::wstring& value,
                 std::array<std::uint8_t, 32>* digest) {
  if (value.size() != digest->size() * 2) return false;
  auto nibble = [](wchar_t character) -> int {
    if (character >= L'0' && character <= L'9') return character - L'0';
    if (character >= L'a' && character <= L'f') return character - L'a' + 10;
    if (character >= L'A' && character <= L'F') return character - L'A' + 10;
    return -1;
  };
  for (size_t index = 0; index < digest->size(); ++index) {
    const int high = nibble(value[index * 2]);
    const int low = nibble(value[index * 2 + 1]);
    if (high < 0 || low < 0) return false;
    (*digest)[index] = static_cast<std::uint8_t>((high << 4) | low);
  }
  return true;
}

bool VerifySha256(const std::vector<std::uint8_t>& bytes,
                  const std::wstring& expected_text) {
  std::array<std::uint8_t, 32> expected = {};
  if (!ParseSha256(expected_text, &expected)) return false;

  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  DWORD object_size = 0;
  DWORD copied = 0;
  bool success = false;
  if (!BCRYPT_SUCCESS(::BCryptOpenAlgorithmProvider(
          &algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0)) ||
      !BCRYPT_SUCCESS(::BCryptGetProperty(
          algorithm, BCRYPT_OBJECT_LENGTH,
          reinterpret_cast<PUCHAR>(&object_size), sizeof(object_size), &copied,
          0))) {
    if (algorithm != nullptr) ::BCryptCloseAlgorithmProvider(algorithm, 0);
    return false;
  }
  std::vector<std::uint8_t> object(object_size);
  std::array<std::uint8_t, 32> actual = {};
  if (BCRYPT_SUCCESS(::BCryptCreateHash(
          algorithm, &hash, object.data(), static_cast<ULONG>(object.size()),
          nullptr, 0, 0)) &&
      BCRYPT_SUCCESS(::BCryptHashData(
          hash, const_cast<PUCHAR>(bytes.data()),
          static_cast<ULONG>(bytes.size()), 0)) &&
      BCRYPT_SUCCESS(::BCryptFinishHash(
          hash, actual.data(), static_cast<ULONG>(actual.size()), 0))) {
    success = std::equal(actual.begin(), actual.end(), expected.begin());
  }
  if (hash != nullptr) ::BCryptDestroyHash(hash);
  ::BCryptCloseAlgorithmProvider(algorithm, 0);
  return success;
}

class BinaryReader {
 public:
  explicit BinaryReader(const std::vector<std::uint8_t>& bytes)
      : bytes_(bytes) {}

  bool ReadBytes(size_t length, const std::uint8_t** value) {
    if (length > bytes_.size() - offset_) return false;
    *value = bytes_.data() + offset_;
    offset_ += length;
    return true;
  }

  bool ReadUint32(std::uint32_t* value) {
    const std::uint8_t* bytes = nullptr;
    if (!ReadBytes(sizeof(*value), &bytes)) return false;
    *value = static_cast<std::uint32_t>(bytes[0]) |
             (static_cast<std::uint32_t>(bytes[1]) << 8) |
             (static_cast<std::uint32_t>(bytes[2]) << 16) |
             (static_cast<std::uint32_t>(bytes[3]) << 24);
    return true;
  }

  bool ReadInt32(std::int32_t* value) {
    std::uint32_t raw = 0;
    if (!ReadUint32(&raw)) return false;
    std::memcpy(value, &raw, sizeof(raw));
    return true;
  }

  bool ReadString(std::optional<std::string>* value) {
    std::uint32_t length = 0;
    if (!ReadUint32(&length)) return false;
    if (length == kAbsentStringLength) {
      value->reset();
      return true;
    }
    const std::uint8_t* bytes = nullptr;
    if (!ReadBytes(length, &bytes)) return false;
    *value = std::string(reinterpret_cast<const char*>(bytes), length);
    return true;
  }

  bool at_end() const { return offset_ == bytes_.size(); }

 private:
  const std::vector<std::uint8_t>& bytes_;
  size_t offset_ = 0;
};

enum class MutationType : std::uint32_t { kUpsert = 1, kRelocate = 2, kRemove = 3 };

struct MutationOperation {
  MutationType type = MutationType::kRemove;
  std::int32_t visibility = -1;
  std::wstring name;
  std::wstring reg_key;
  std::optional<std::wstring> snpid;
  std::optional<std::wstring> content_path;
  std::optional<std::wstring> product_hints_xml;
  std::optional<std::wstring> hu;
  std::optional<std::wstring> jdx;
  std::optional<std::wstring> upid;
  std::optional<std::wstring> auth_system;
};

struct MutationRequest {
  bool is_batch = false;
  std::vector<MutationOperation> operations;
};

bool ConvertOptionalString(const std::optional<std::string>& source,
                           std::optional<std::wstring>* target) {
  if (!source.has_value()) {
    target->reset();
    return true;
  }
  const auto converted = Utf16FromUtf8(*source);
  if (!converted.has_value()) return false;
  *target = *converted;
  return true;
}

bool DecodeRequest(const std::vector<std::uint8_t>& bytes,
                   MutationRequest* request) {
  BinaryReader reader(bytes);
  const std::uint8_t* magic = nullptr;
  if (!reader.ReadBytes(kRequestMagic.size(), &magic) ||
      !std::equal(kRequestMagic.begin(), kRequestMagic.end(), magic)) {
    return false;
  }
  std::uint32_t version = 0;
  std::uint32_t flags = 0;
  std::uint32_t operation_count = 0;
  if (!reader.ReadUint32(&version) || !reader.ReadUint32(&flags) ||
      !reader.ReadUint32(&operation_count) || version != 1 || flags > 1 ||
      operation_count == 0 || operation_count > kMaximumOperations ||
      (flags == 0 && operation_count != 1)) {
    return false;
  }
  request->is_batch = flags == 1;
  request->operations.reserve(operation_count);
  for (std::uint32_t index = 0; index < operation_count; ++index) {
    std::uint32_t raw_type = 0;
    MutationOperation operation;
    if (!reader.ReadUint32(&raw_type) ||
        !reader.ReadInt32(&operation.visibility) || raw_type < 1 ||
        raw_type > 3) {
      return false;
    }
    operation.type = static_cast<MutationType>(raw_type);
    std::array<std::optional<std::string>, 9> raw_strings;
    for (auto& raw_string : raw_strings) {
      if (!reader.ReadString(&raw_string)) return false;
    }
    const auto name = raw_strings[0].has_value()
                          ? Utf16FromUtf8(*raw_strings[0])
                          : std::nullopt;
    const auto reg_key = raw_strings[1].has_value()
                             ? Utf16FromUtf8(*raw_strings[1])
                             : std::nullopt;
    if (!name.has_value() || !reg_key.has_value()) return false;
    operation.name = *name;
    operation.reg_key = *reg_key;
    if (!ConvertOptionalString(raw_strings[2], &operation.snpid) ||
        !ConvertOptionalString(raw_strings[3], &operation.content_path) ||
        !ConvertOptionalString(raw_strings[4],
                               &operation.product_hints_xml) ||
        !ConvertOptionalString(raw_strings[5], &operation.hu) ||
        !ConvertOptionalString(raw_strings[6], &operation.jdx) ||
        !ConvertOptionalString(raw_strings[7], &operation.upid) ||
        !ConvertOptionalString(raw_strings[8], &operation.auth_system)) {
      return false;
    }
    request->operations.emplace_back(std::move(operation));
  }
  return reader.at_end();
}

bool IsSafeComponent(const std::wstring& value) {
  if (value.empty() || value.size() > 255 || value == L"." || value == L".." ||
      value.back() == L'.' || value.back() == L' ' ||
      value.find_first_of(L"<>:\"/\\|?*") != std::wstring::npos ||
      value.find(L'\0') != std::wstring::npos) {
    return false;
  }
  return std::none_of(value.begin(), value.end(), [](wchar_t character) {
    return std::iswcntrl(character) != 0;
  });
}

bool NormalizeSafeComponent(std::wstring* value) {
  *value = Trim(*value);
  return IsSafeComponent(*value);
}

bool NormalizeOptionalSafeComponent(std::optional<std::wstring>* value) {
  if (!value->has_value()) return true;
  **value = Trim(**value);
  return IsSafeComponent(**value);
}

bool NormalizeContentDirectory(std::optional<std::wstring>* value) {
  if (!value->has_value() || value->value().size() > 4096) return false;
  const std::wstring full_path = FullPath(**value);
  if (full_path.empty() || full_path.size() < 3 || full_path[1] != L':' ||
      (full_path[2] != L'\\' && full_path[2] != L'/')) {
    return false;
  }
  const DWORD attributes = ::GetFileAttributesW(full_path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
    return false;
  }
  *value = full_path;
  return true;
}

std::optional<std::wstring> KnownFolder(REFKNOWNFOLDERID folder_id) {
  PWSTR value = nullptr;
  if (FAILED(::SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr,
                                    &value)) ||
      value == nullptr) {
    return std::nullopt;
  }
  std::wstring path(value);
  ::CoTaskMemFree(value);
  return path;
}

std::optional<std::wstring> XmlNodeText(IXMLDOMDocument2* document,
                                        const wchar_t* xpath) {
  BSTR expression = ::SysAllocString(xpath);
  if (expression == nullptr) return std::nullopt;
  ComPtr<IXMLDOMNode> node;
  const HRESULT selected = document->selectSingleNode(expression, &node);
  ::SysFreeString(expression);
  if (selected != S_OK || node == nullptr) return std::nullopt;
  BSTR text = nullptr;
  if (FAILED(node->get_text(&text)) || text == nullptr) return std::nullopt;
  std::wstring value(text, ::SysStringLen(text));
  ::SysFreeString(text);
  return Trim(value);
}

bool ValidateProductHints(const std::wstring& xml, const std::wstring& name,
                          const std::wstring& reg_key,
                          const std::wstring& snpid) {
  const auto utf8 = Utf8FromUtf16(xml);
  if (!utf8.has_value() || utf8->size() > 2000000) return false;
  const std::wstring lowered = Lower(xml);
  if (lowered.find(L"<!doctype") != std::wstring::npos ||
      lowered.find(L"<!entity") != std::wstring::npos) {
    return false;
  }

  ComPtr<IXMLDOMDocument2> document;
  if (FAILED(::CoCreateInstance(CLSID_DOMDocument60, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&document))) ||
      document == nullptr) {
    return false;
  }
  document->put_async(VARIANT_FALSE);
  document->put_validateOnParse(VARIANT_FALSE);
  document->put_resolveExternals(VARIANT_FALSE);
  VARIANT prohibit_dtd;
  ::VariantInit(&prohibit_dtd);
  prohibit_dtd.vt = VT_BOOL;
  prohibit_dtd.boolVal = VARIANT_TRUE;
  BSTR property_name = ::SysAllocString(L"ProhibitDTD");
  if (property_name == nullptr ||
      FAILED(document->setProperty(property_name, prohibit_dtd))) {
    if (property_name != nullptr) ::SysFreeString(property_name);
    return false;
  }
  ::SysFreeString(property_name);

  BSTR xml_text = ::SysAllocStringLen(xml.data(), static_cast<UINT>(xml.size()));
  if (xml_text == nullptr) return false;
  VARIANT_BOOL loaded = VARIANT_FALSE;
  const HRESULT load_result = document->loadXML(xml_text, &loaded);
  ::SysFreeString(xml_text);
  if (FAILED(load_result) || loaded != VARIANT_TRUE) return false;

  BSTR products_xpath = ::SysAllocString(L"/ProductHints/Product");
  if (products_xpath == nullptr) return false;
  ComPtr<IXMLDOMNodeList> products;
  const HRESULT selection = document->selectNodes(products_xpath, &products);
  ::SysFreeString(products_xpath);
  long product_count = 0;
  if (selection != S_OK || products == nullptr ||
      FAILED(products->get_length(&product_count)) || product_count != 1) {
    return false;
  }

  return XmlNodeText(document.Get(), L"/ProductHints/Product/Name") == name &&
         XmlNodeText(document.Get(), L"/ProductHints/Product/RegKey") ==
             reg_key &&
         XmlNodeText(document.Get(), L"/ProductHints/Product/SNPID") == snpid;
}

bool ValidateOperations(MutationRequest* request, std::wstring* error) {
  for (MutationOperation& operation : request->operations) {
    if (!NormalizeSafeComponent(&operation.name) ||
        !NormalizeSafeComponent(&operation.reg_key)) {
      *error = L"The library name or registry key is invalid.";
      return false;
    }
    if (operation.visibility < -1 || operation.visibility > 255 ||
        !NormalizeOptionalSafeComponent(&operation.snpid) ||
        !NormalizeOptionalSafeComponent(&operation.hu) ||
        !NormalizeOptionalSafeComponent(&operation.jdx) ||
        !NormalizeOptionalSafeComponent(&operation.upid) ||
        !NormalizeOptionalSafeComponent(&operation.auth_system)) {
      *error = L"The library metadata is invalid.";
      return false;
    }

    if (operation.type == MutationType::kUpsert) {
      if (!operation.snpid.has_value() ||
          !NormalizeContentDirectory(&operation.content_path) ||
          !operation.product_hints_xml.has_value() ||
          !ValidateProductHints(*operation.product_hints_xml, operation.name,
                                operation.reg_key, *operation.snpid)) {
        *error = L"The Kontakt library metadata is invalid.";
        return false;
      }
      if (operation.visibility == -1) operation.visibility = 3;
    } else if (operation.type == MutationType::kRelocate) {
      if (!NormalizeContentDirectory(&operation.content_path)) {
        *error = L"The Kontakt content directory is invalid or does not exist.";
        return false;
      }
    }
  }
  return true;
}

struct FileChange {
  std::wstring path;
  std::optional<std::string> contents;
};

struct RegistryStringValue {
  std::wstring name;
  std::wstring value;
};

struct MutationPlan {
  MutationOperation operation;
  std::vector<FileChange> file_changes;
  std::vector<RegistryStringValue> registry_strings;
  DWORD visibility = 0;
  bool has_visibility = false;
  bool remove_registry = false;
  bool has_registry32 = false;
};

std::string JsonEscapeUtf8(const std::wstring& value) {
  const auto utf8 = Utf8FromUtf16(value);
  if (!utf8.has_value()) return {};
  static constexpr char kHex[] = "0123456789abcdef";
  std::string escaped;
  escaped.reserve(utf8->size() + 8);
  for (const unsigned char character : *utf8) {
    switch (character) {
      case '"':
        escaped += "\\\"";
        break;
      case '\\':
        escaped += "\\\\";
        break;
      case '\b':
        escaped += "\\b";
        break;
      case '\f':
        escaped += "\\f";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        if (character < 0x20) {
          escaped += "\\u00";
          escaped.push_back(kHex[(character >> 4) & 0x0f]);
          escaped.push_back(kHex[character & 0x0f]);
        } else {
          escaped.push_back(static_cast<char>(character));
        }
    }
  }
  return escaped;
}

bool IsJsonWhitespace(char character) {
  return character == ' ' || character == '\t' || character == '\r' ||
         character == '\n';
}

size_t SkipJsonWhitespace(const std::string& text, size_t position) {
  while (position < text.size() && IsJsonWhitespace(text[position])) {
    ++position;
  }
  return position;
}

int JsonHexValue(char character) {
  if (character >= '0' && character <= '9') return character - '0';
  if (character >= 'a' && character <= 'f') return character - 'a' + 10;
  if (character >= 'A' && character <= 'F') return character - 'A' + 10;
  return -1;
}

bool ParseJsonString(const std::string& text, size_t start, size_t* end,
                     std::string* value) {
  if (start >= text.size() || text[start] != '"') return false;
  value->clear();
  for (size_t position = start + 1; position < text.size(); ++position) {
    const unsigned char character =
        static_cast<unsigned char>(text[position]);
    if (character == '"') {
      *end = position + 1;
      return true;
    }
    if (character < 0x20) return false;
    if (character != '\\') {
      value->push_back(static_cast<char>(character));
      continue;
    }
    if (++position >= text.size()) return false;
    switch (text[position]) {
      case '"':
      case '\\':
      case '/':
        value->push_back(text[position]);
        break;
      case 'b':
        value->push_back('\b');
        break;
      case 'f':
        value->push_back('\f');
        break;
      case 'n':
        value->push_back('\n');
        break;
      case 'r':
        value->push_back('\r');
        break;
      case 't':
        value->push_back('\t');
        break;
      case 'u': {
        if (position + 4 >= text.size()) return false;
        unsigned value_code = 0;
        for (size_t offset = 1; offset <= 4; ++offset) {
          const int nibble = JsonHexValue(text[position + offset]);
          if (nibble < 0) return false;
          value_code = (value_code << 4) | static_cast<unsigned>(nibble);
        }
        if (value_code <= 0x7f) {
          value->push_back(static_cast<char>(value_code));
        } else {
          // Product field names are ASCII. Keep non-ASCII escaped keys from
          // being mistaken for ContentDir while still parsing the document.
          value->push_back('?');
        }
        position += 4;
        break;
      }
      default:
        return false;
    }
  }
  return false;
}

bool SkipJsonValue(const std::string& text, size_t start, size_t* end) {
  if (start >= text.size()) return false;
  if (text[start] == '"') {
    std::string ignored;
    return ParseJsonString(text, start, end, &ignored);
  }
  if (text[start] == '{' || text[start] == '[') {
    std::vector<char> containers;
    for (size_t position = start; position < text.size(); ++position) {
      const char character = text[position];
      if (character == '"') {
        size_t string_end = 0;
        std::string ignored;
        if (!ParseJsonString(text, position, &string_end, &ignored)) {
          return false;
        }
        position = string_end - 1;
        continue;
      }
      if (character == '{' || character == '[') {
        containers.push_back(character);
        continue;
      }
      if (character != '}' && character != ']') continue;
      if (containers.empty() ||
          (character == '}' && containers.back() != '{') ||
          (character == ']' && containers.back() != '[')) {
        return false;
      }
      containers.pop_back();
      if (containers.empty()) {
        *end = position + 1;
        return true;
      }
    }
    return false;
  }
  size_t position = start;
  while (position < text.size() && !IsJsonWhitespace(text[position]) &&
         text[position] != ',' && text[position] != '}' &&
         text[position] != ']') {
    ++position;
  }
  if (position == start) return false;
  *end = position;
  return true;
}

std::optional<std::string> UpdateContentDirectoryJson(
    const std::vector<std::uint8_t>& bytes,
    const std::wstring& content_path) {
  std::string text(bytes.begin(), bytes.end());
  size_t root = SkipJsonWhitespace(text, 0);
  if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xef &&
      static_cast<unsigned char>(text[1]) == 0xbb &&
      static_cast<unsigned char>(text[2]) == 0xbf) {
    root = SkipJsonWhitespace(text, 3);
  }
  if (root >= text.size() || text[root] != '{') return std::nullopt;

  const std::string replacement_value =
      "\"" + JsonEscapeUtf8(content_path) + "\"";
  size_t position = root + 1;
  bool has_member = false;
  bool found_content_directory = false;
  bool expect_member = false;
  size_t closing_brace = std::string::npos;
  while (true) {
    position = SkipJsonWhitespace(text, position);
    if (position >= text.size()) return std::nullopt;
    if (text[position] == '}') {
      if (expect_member) return std::nullopt;
      closing_brace = position;
      break;
    }
    std::string key;
    const size_t key_start = position;
    size_t key_end = 0;
    if (!ParseJsonString(text, position, &key_end, &key)) {
      return std::nullopt;
    }
    if (key == "contentDir") {
      const std::string canonical_key = "\"ContentDir\"";
      text.replace(key_start, key_end - key_start, canonical_key);
      key_end = key_start + canonical_key.size();
    }
    position = SkipJsonWhitespace(text, key_end);
    if (position >= text.size() || text[position] != ':') {
      return std::nullopt;
    }
    position = SkipJsonWhitespace(text, position + 1);
    const size_t value_start = position;
    size_t value_end = 0;
    if (!SkipJsonValue(text, value_start, &value_end)) return std::nullopt;
    expect_member = false;
    if (key == "ContentDir" || key == "contentDir") {
      if (found_content_directory) return std::nullopt;
      found_content_directory = true;
      text.replace(value_start, value_end - value_start, replacement_value);
      position = value_start + replacement_value.size();
    } else {
      position = value_end;
    }
    has_member = true;
    position = SkipJsonWhitespace(text, position);
    if (position >= text.size()) return std::nullopt;
    if (text[position] == ',') {
      ++position;
      expect_member = true;
      continue;
    }
    if (text[position] == '}') {
      expect_member = false;
      closing_brace = position;
      break;
    }
    return std::nullopt;
  }

  if (closing_brace == std::string::npos ||
      SkipJsonWhitespace(text, closing_brace + 1) != text.size()) {
    return std::nullopt;
  }
  if (!found_content_directory) {
    std::string insertion;
    if (has_member) insertion = ",";
    insertion += "\"ContentDir\":\"" + JsonEscapeUtf8(content_path) +
                 "\"";
    text.insert(closing_brace, insertion);
  }
  return text;
}

std::optional<std::string> ContentDirectoryJson(
    const std::wstring& json_path, const std::wstring& content_path,
    std::wstring* error) {
  const DWORD attributes = ::GetFileAttributesW(json_path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD last_error = ::GetLastError();
    if (last_error == ERROR_FILE_NOT_FOUND ||
        last_error == ERROR_PATH_NOT_FOUND) {
      return "{\"ContentDir\":\"" + JsonEscapeUtf8(content_path) + "\"}";
    }
    *error = L"The existing installed_products JSON could not be read.";
    return std::nullopt;
  }
  if ((attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) !=
      0) {
    *error = L"The installed_products JSON target is not a regular file.";
    return std::nullopt;
  }
  std::vector<std::uint8_t> bytes;
  if (!ReadFileBytes(json_path, kMaximumRequestBytes, &bytes)) {
    *error = L"The existing installed_products JSON could not be backed up.";
    return std::nullopt;
  }
  const auto updated = UpdateContentDirectoryJson(bytes, content_path);
  if (!updated.has_value()) {
    *error = L"The existing installed_products JSON is invalid or unsupported.";
    return std::nullopt;
  }
  return updated;
}

bool RegistryKeyExists(REGSAM view, const std::wstring& reg_key) {
  HKEY raw_key = nullptr;
  const std::wstring path =
      std::wstring(kNativeInstrumentsKey) + L"\\" + reg_key;
  const LONG status = ::RegOpenKeyExW(HKEY_LOCAL_MACHINE, path.c_str(), 0,
                                      KEY_READ | view, &raw_key);
  if (status == ERROR_SUCCESS) ::RegCloseKey(raw_key);
  return status == ERROR_SUCCESS;
}

std::optional<std::vector<MutationPlan>> BuildPlans(
    const MutationRequest& request, std::wstring* error) {
  const auto program_files = KnownFolder(FOLDERID_ProgramFiles);
  const auto public_documents = KnownFolder(FOLDERID_PublicDocuments);
  if (!program_files.has_value() || !public_documents.has_value()) {
    *error = L"The Windows library locations could not be resolved.";
    return std::nullopt;
  }
  const std::wstring service_directory = JoinPath(
      *program_files, L"Common Files\\Native Instruments\\Service Center");
  const std::wstring products_directory = JoinPath(
      *public_documents, L"Native Instruments\\installed_products");

  std::vector<MutationPlan> plans;
  plans.reserve(request.operations.size());
  std::unordered_map<std::wstring, bool> file_targets;
  std::unordered_map<std::wstring, bool> registry_targets;
  for (const MutationOperation& operation : request.operations) {
    MutationPlan plan;
    plan.operation = operation;
    plan.remove_registry = operation.type == MutationType::kRemove;
    plan.has_registry32 = RegistryKeyExists(KEY_WOW64_32KEY, operation.reg_key);
    const std::wstring xml_path =
        JoinPath(service_directory, operation.name + L".xml");
    const std::wstring json_path =
        JoinPath(products_directory, operation.name + L".json");

    if (operation.type == MutationType::kUpsert) {
      const auto xml_utf8 = Utf8FromUtf16(*operation.product_hints_xml);
      if (!xml_utf8.has_value()) {
        *error = L"The ProductHints XML encoding is invalid.";
        return std::nullopt;
      }
      const auto json = ContentDirectoryJson(
          json_path, *operation.content_path, error);
      if (!json.has_value()) return std::nullopt;
      plan.file_changes.push_back(FileChange{xml_path, *xml_utf8});
      plan.file_changes.push_back(FileChange{json_path, *json});
      plan.registry_strings = {
          {L"Name", operation.name},
          {L"RegKey", operation.reg_key},
          {L"SNPID", *operation.snpid},
          {L"ContentDir", *operation.content_path},
      };
      if (operation.hu.has_value()) {
        plan.registry_strings.push_back({L"HU", *operation.hu});
      }
      if (operation.jdx.has_value()) {
        plan.registry_strings.push_back({L"JDX", *operation.jdx});
      }
      if (operation.upid.has_value()) {
        plan.registry_strings.push_back({L"UPID", *operation.upid});
      }
      if (operation.auth_system.has_value()) {
        plan.registry_strings.push_back(
            {L"AuthSystem", *operation.auth_system});
      }
      plan.has_visibility = true;
      plan.visibility = static_cast<DWORD>(operation.visibility);
    } else if (operation.type == MutationType::kRelocate) {
      const auto json = ContentDirectoryJson(
          json_path, *operation.content_path, error);
      if (!json.has_value()) return std::nullopt;
      plan.file_changes.push_back(FileChange{json_path, *json});
      plan.registry_strings = {
          {L"Name", operation.name},
          {L"RegKey", operation.reg_key},
          {L"ContentDir", *operation.content_path},
      };
      if (operation.snpid.has_value()) {
        plan.registry_strings.push_back({L"SNPID", *operation.snpid});
      }
    } else {
      plan.file_changes.push_back(FileChange{xml_path, std::nullopt});
      plan.file_changes.push_back(FileChange{json_path, std::nullopt});
    }

    for (const FileChange& change : plan.file_changes) {
      const std::wstring identity = Lower(FullPath(change.path));
      const bool removes = !change.contents.has_value();
      const auto existing = file_targets.find(identity);
      if (existing != file_targets.end() &&
          (!removes || !existing->second)) {
        *error = L"The mutation contains conflicting file targets.";
        return std::nullopt;
      }
      file_targets.emplace(identity, removes);
    }
    for (const REGSAM view :
         plan.has_registry32
             ? std::vector<REGSAM>{KEY_WOW64_64KEY, KEY_WOW64_32KEY}
             : std::vector<REGSAM>{KEY_WOW64_64KEY}) {
      const std::wstring identity = std::to_wstring(view) + L"|" +
                                    Lower(operation.reg_key);
      const auto existing = registry_targets.find(identity);
      if (existing != registry_targets.end() &&
          (!plan.remove_registry || !existing->second)) {
        *error = L"The mutation contains conflicting registry targets.";
        return std::nullopt;
      }
      registry_targets.emplace(identity, plan.remove_registry);
    }
    plans.emplace_back(std::move(plan));
  }
  return plans;
}

bool EnsureDirectory(const std::wstring& input) {
  const std::wstring path = FullPath(input);
  if (path.empty() || PathHasReparsePoint(path)) return false;
  std::wstring current;
  if (path.size() >= 3 && path[1] == L':' &&
      (path[2] == L'\\' || path[2] == L'/')) {
    current = path.substr(0, 3);
  } else {
    std::vector<wchar_t> root_buffer(MAX_PATH, L'\0');
    if (!::GetVolumePathNameW(path.c_str(), root_buffer.data(),
                              static_cast<DWORD>(root_buffer.size()))) {
      return false;
    }
    current = root_buffer.data();
  }
  size_t position = current.size();
  while (position < path.size()) {
    while (position < path.size() &&
           (path[position] == L'\\' || path[position] == L'/')) {
      ++position;
    }
    if (position >= path.size()) break;
    const size_t separator = path.find_first_of(L"\\/", position);
    const size_t end = separator == std::wstring::npos ? path.size() : separator;
    current = JoinPath(current, path.substr(position, end - position));
    DWORD attributes = ::GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      if (!::CreateDirectoryW(current.c_str(), nullptr) &&
          ::GetLastError() != ERROR_ALREADY_EXISTS) {
        return false;
      }
      attributes = ::GetFileAttributesW(current.c_str());
    }
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      return false;
    }
    position = end;
  }
  return !PathHasReparsePoint(path);
}

bool WriteBytes(HANDLE file, const std::vector<std::uint8_t>& bytes) {
  size_t offset = 0;
  while (offset < bytes.size()) {
    const size_t remaining = bytes.size() - offset;
    const DWORD chunk = static_cast<DWORD>(std::min<size_t>(remaining, MAXDWORD));
    DWORD written = 0;
    if (!::WriteFile(file, bytes.data() + offset, chunk, &written, nullptr) ||
        written != chunk) {
      return false;
    }
    offset += written;
  }
  return ::FlushFileBuffers(file) != FALSE;
}

std::wstring TemporarySiblingPath(const std::wstring& target) {
  GUID guid = {};
  if (FAILED(::CoCreateGuid(&guid))) return {};
  wchar_t guid_text[40] = {};
  if (::StringFromGUID2(guid, guid_text,
                        static_cast<int>(std::size(guid_text))) <= 0) {
    return {};
  }
  std::wstring compact;
  for (const wchar_t character : std::wstring(guid_text)) {
    if (std::iswxdigit(character) != 0) compact.push_back(character);
  }
  return JoinPath(ParentPath(target), L".klm-" + compact + L".tmp");
}

bool WriteFileAtomic(const std::wstring& target,
                     const std::vector<std::uint8_t>& bytes) {
  const std::wstring parent = ParentPath(target);
  if (!EnsureDirectory(parent)) return false;
  const DWORD target_attributes = ::GetFileAttributesW(target.c_str());
  if (target_attributes != INVALID_FILE_ATTRIBUTES &&
      (target_attributes &
       (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return false;
  }
  const std::wstring temporary = TemporarySiblingPath(target);
  if (temporary.empty()) return false;
  bool success = false;
  {
    ScopedHandle file(::CreateFileW(
        temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
        FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_WRITE_THROUGH, nullptr));
    success = file && WriteBytes(file.get(), bytes);
  }
  if (success && target_attributes != INVALID_FILE_ATTRIBUTES) {
    ::SetFileAttributesW(target.c_str(), FILE_ATTRIBUTE_NORMAL);
  }
  if (success) {
    success = ::MoveFileExW(temporary.c_str(), target.c_str(),
                            MOVEFILE_REPLACE_EXISTING |
                                MOVEFILE_WRITE_THROUGH) != FALSE;
  }
  if (!success) ::DeleteFileW(temporary.c_str());
  return success;
}

bool RemoveRegularFile(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = ::GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
  }
  if ((attributes &
       (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return false;
  }
  ::SetFileAttributesW(path.c_str(), FILE_ATTRIBUTE_NORMAL);
  return ::DeleteFileW(path.c_str()) != FALSE;
}

struct FileBackup {
  std::wstring path;
  bool existed = false;
  std::vector<std::uint8_t> bytes;
};

bool CaptureFileBackup(const std::wstring& path, FileBackup* backup) {
  backup->path = path;
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = ::GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
  }
  if ((attributes &
       (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0) {
    return false;
  }
  backup->existed = true;
  return ReadFileBytes(path, kMaximumBackupBytes, &backup->bytes);
}

void RestoreFileBackup(const FileBackup& backup) {
  if (backup.existed) {
    WriteFileAtomic(backup.path, backup.bytes);
  } else {
    RemoveRegularFile(backup.path);
  }
}

struct RegistryValueBackup {
  std::wstring name;
  DWORD type = REG_NONE;
  std::vector<std::uint8_t> data;
};

struct RegistryBackup {
  REGSAM view = 0;
  std::wstring reg_key;
  bool existed = false;
  std::vector<RegistryValueBackup> values;
};

bool CaptureRegistryBackup(REGSAM view, const std::wstring& reg_key,
                           RegistryBackup* backup) {
  backup->view = view;
  backup->reg_key = reg_key;
  const std::wstring path =
      std::wstring(kNativeInstrumentsKey) + L"\\" + reg_key;
  HKEY raw_key = nullptr;
  const LONG open_status = ::RegOpenKeyExW(
      HKEY_LOCAL_MACHINE, path.c_str(), 0, KEY_QUERY_VALUE | view, &raw_key);
  if (open_status == ERROR_FILE_NOT_FOUND) return true;
  if (open_status != ERROR_SUCCESS) return false;
  backup->existed = true;
  ScopedRegistryKey key(raw_key);

  DWORD value_count = 0;
  DWORD maximum_name = 0;
  DWORD maximum_data = 0;
  if (::RegQueryInfoKeyW(key.get(), nullptr, nullptr, nullptr, nullptr, nullptr,
                         nullptr, &value_count, &maximum_name, &maximum_data,
                         nullptr, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  std::vector<wchar_t> name(static_cast<size_t>(maximum_name) + 2, L'\0');
  std::vector<std::uint8_t> data(static_cast<size_t>(maximum_data) + 2, 0);
  for (DWORD index = 0; index < value_count; ++index) {
    DWORD name_length = static_cast<DWORD>(name.size());
    DWORD data_length = static_cast<DWORD>(data.size());
    DWORD type = REG_NONE;
    const LONG status = ::RegEnumValueW(
        key.get(), index, name.data(), &name_length, nullptr, &type, data.data(),
        &data_length);
    if (status != ERROR_SUCCESS) return false;
    backup->values.push_back(RegistryValueBackup{
        std::wstring(name.data(), name_length), type,
        std::vector<std::uint8_t>(data.begin(), data.begin() + data_length)});
  }
  return true;
}

ScopedRegistryKey OpenNativeInstrumentsRoot(REGSAM view, REGSAM access,
                                             bool create) {
  HKEY raw_key = nullptr;
  const LONG status = create
                          ? ::RegCreateKeyExW(
                                HKEY_LOCAL_MACHINE, kNativeInstrumentsKey, 0,
                                nullptr, REG_OPTION_NON_VOLATILE, access | view,
                                nullptr, &raw_key, nullptr)
                          : ::RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                                            kNativeInstrumentsKey, 0,
                                            access | view, &raw_key);
  return status == ERROR_SUCCESS ? ScopedRegistryKey(raw_key)
                                 : ScopedRegistryKey();
}

bool SetRegistryString(HKEY key, const std::wstring& name,
                       const std::wstring& value) {
  const size_t byte_count = (value.size() + 1) * sizeof(wchar_t);
  if (byte_count > MAXDWORD) return false;
  return ::RegSetValueExW(key, name.c_str(), 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(value.c_str()),
                          static_cast<DWORD>(byte_count)) == ERROR_SUCCESS;
}

bool ApplyRegistryPlan(const MutationPlan& plan, REGSAM view) {
  ScopedRegistryKey root = OpenNativeInstrumentsRoot(
      view, KEY_READ | KEY_WRITE | KEY_CREATE_SUB_KEY | DELETE, true);
  if (!root) return false;
  if (plan.remove_registry) {
    const LONG status = ::RegDeleteTreeW(root.get(), plan.operation.reg_key.c_str());
    return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
  }

  HKEY raw_key = nullptr;
  if (::RegCreateKeyExW(root.get(), plan.operation.reg_key.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_READ | KEY_WRITE, nullptr,
                        &raw_key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  ScopedRegistryKey key(raw_key);
  for (const RegistryStringValue& value : plan.registry_strings) {
    if (!SetRegistryString(key.get(), value.name, value.value)) return false;
  }
  if (plan.has_visibility &&
      ::RegSetValueExW(
          key.get(), L"Visibility", 0, REG_DWORD,
          reinterpret_cast<const BYTE*>(&plan.visibility),
          sizeof(plan.visibility)) != ERROR_SUCCESS) {
    return false;
  }
  return true;
}

void RestoreRegistryBackup(const RegistryBackup& backup) {
  ScopedRegistryKey root = OpenNativeInstrumentsRoot(
      backup.view, KEY_READ | KEY_WRITE | KEY_CREATE_SUB_KEY | DELETE, true);
  if (!root) return;
  ::RegDeleteTreeW(root.get(), backup.reg_key.c_str());
  if (!backup.existed) return;
  HKEY raw_key = nullptr;
  if (::RegCreateKeyExW(root.get(), backup.reg_key.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_READ | KEY_WRITE, nullptr,
                        &raw_key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  ScopedRegistryKey key(raw_key);
  for (const RegistryValueBackup& value : backup.values) {
    ::RegSetValueExW(key.get(), value.name.c_str(), 0, value.type,
                     value.data.data(),
                     static_cast<DWORD>(value.data.size()));
  }
}

struct MutationResult {
  MutationType operation = MutationType::kRemove;
  std::wstring library_name;
  std::vector<std::wstring> changed_paths;
};

const char* OperationName(MutationType operation) {
  switch (operation) {
    case MutationType::kUpsert:
      return "upsert";
    case MutationType::kRelocate:
      return "relocate";
    case MutationType::kRemove:
      return "remove";
  }
  return "remove";
}

bool ApplyPlans(const std::vector<MutationPlan>& plans,
                std::vector<MutationResult>* results, std::wstring* error) {
  std::unordered_set<std::wstring> applied_files;
  std::unordered_set<std::wstring> applied_registry;
  std::vector<FileBackup> file_backups;
  std::vector<RegistryBackup> registry_backups;
  bool success = true;

  for (const MutationPlan& plan : plans) {
    MutationResult result;
    result.operation = plan.operation.type;
    result.library_name = plan.operation.name;
    for (const FileChange& change : plan.file_changes) {
      const std::wstring identity = Lower(FullPath(change.path));
      if (applied_files.insert(identity).second) {
        if (PathHasReparsePoint(ParentPath(change.path))) {
          success = false;
          *error = L"A reparse point was rejected in a library metadata path.";
          break;
        }
        FileBackup backup;
        if (!CaptureFileBackup(change.path, &backup)) {
          success = false;
          *error = L"A library metadata backup could not be created.";
          break;
        }
        file_backups.emplace_back(std::move(backup));
        if (change.contents.has_value()) {
          const std::vector<std::uint8_t> contents(change.contents->begin(),
                                                   change.contents->end());
          success = WriteFileAtomic(change.path, contents);
        } else {
          success = RemoveRegularFile(change.path);
        }
        if (!success) {
          *error = L"A library metadata file could not be updated.";
          break;
        }
      }
      result.changed_paths.push_back(change.path);
    }
    if (!success) break;

    const std::vector<REGSAM> views =
        plan.has_registry32
            ? std::vector<REGSAM>{KEY_WOW64_64KEY, KEY_WOW64_32KEY}
            : std::vector<REGSAM>{KEY_WOW64_64KEY};
    for (const REGSAM view : views) {
      const std::wstring identity = std::to_wstring(view) + L"|" +
                                    Lower(plan.operation.reg_key);
      if (applied_registry.insert(identity).second) {
        RegistryBackup backup;
        if (!CaptureRegistryBackup(view, plan.operation.reg_key, &backup)) {
          success = false;
          *error = L"A Native Instruments registry backup could not be created.";
          break;
        }
        registry_backups.emplace_back(std::move(backup));
        if (!ApplyRegistryPlan(plan, view)) {
          success = false;
          *error = L"The Native Instruments registry could not be updated.";
          break;
        }
      }
      result.changed_paths.push_back(
          std::wstring(L"HKLM [") +
          (view == KEY_WOW64_32KEY ? L"Registry32" : L"Registry64") +
          L"]\\SOFTWARE\\Native Instruments\\" + plan.operation.reg_key);
    }
    if (!success) break;
    results->emplace_back(std::move(result));
  }

  if (!success) {
    for (auto iterator = file_backups.rbegin(); iterator != file_backups.rend();
         ++iterator) {
      RestoreFileBackup(*iterator);
    }
    for (auto iterator = registry_backups.rbegin();
         iterator != registry_backups.rend(); ++iterator) {
      RestoreRegistryBackup(*iterator);
    }
  }
  return success;
}

std::string ResultJson(const MutationResult& result) {
  std::string json = "{\"operation\":\"";
  json += OperationName(result.operation);
  json += "\",\"libraryName\":\"" + JsonEscapeUtf8(result.library_name) +
          "\",\"changedPaths\":[";
  for (size_t index = 0; index < result.changed_paths.size(); ++index) {
    if (index != 0) json.push_back(',');
    json += "\"" + JsonEscapeUtf8(result.changed_paths[index]) + "\"";
  }
  json += "]}";
  return json;
}

std::string SuccessJson(bool is_batch,
                        const std::vector<MutationResult>& results) {
  if (!is_batch) return ResultJson(results.front());
  std::string json = "{\"operation\":\"batch\",\"results\":[";
  for (size_t index = 0; index < results.size(); ++index) {
    if (index != 0) json.push_back(',');
    json += ResultJson(results[index]);
  }
  json += "]}";
  return json;
}

std::string ErrorJson(const std::wstring& message) {
  return "{\"errorCode\":\"mutation_failed\",\"errorMessage\":\"" +
         JsonEscapeUtf8(message) + "\"}";
}

bool WriteResponse(const std::wstring& path, const std::string& json) {
  ScopedHandle file(::CreateFileW(
      path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT |
          FILE_FLAG_WRITE_THROUGH,
      nullptr));
  if (!file) return false;
  const std::vector<std::uint8_t> bytes(json.begin(), json.end());
  return WriteBytes(file.get(), bytes);
}

}  // namespace

int RunNativeMutation(const std::wstring& request_path,
                      const std::wstring& request_sha256,
                      const std::wstring& response_path) {
  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool uninitialize_com = SUCCEEDED(com_result);
  const auto transport = ValidateTransport(request_path, response_path);
  if (!transport.has_value()) {
    if (uninitialize_com) ::CoUninitialize();
    return ERROR_INVALID_PARAMETER;
  }

  bool success = false;
  std::wstring error = L"The native mutation failed.";
  std::vector<std::uint8_t> request_bytes;
  MutationRequest request;
  std::vector<MutationResult> results;
  if (!ReadFileBytes(transport->request, kMaximumRequestBytes,
                     &request_bytes)) {
    error = L"The native mutation request is missing or too large.";
  } else if (!VerifySha256(request_bytes, request_sha256)) {
    error = L"The native mutation request checksum does not match.";
  } else if (!DecodeRequest(request_bytes, &request)) {
    error = L"The native mutation request is invalid.";
  } else if (FAILED(com_result) || !ValidateOperations(&request, &error)) {
    if (FAILED(com_result)) {
      error = L"The Windows XML validator could not be initialized.";
    }
  } else {
    const auto plans = BuildPlans(request, &error);
    if (plans.has_value()) success = ApplyPlans(*plans, &results, &error);
  }

  const std::string response =
      success ? SuccessJson(request.is_batch, results) : ErrorJson(error);
  const bool response_written = WriteResponse(transport->response, response);
  if (uninitialize_com) ::CoUninitialize();
  return success && response_written ? ERROR_SUCCESS : ERROR_GEN_FAILURE;
}
