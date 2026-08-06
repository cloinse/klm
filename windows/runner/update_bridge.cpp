#include "update_bridge.h"

#include <flutter/standard_method_codec.h>

#include <string>

namespace {

constexpr char kChannelName[] =
    "com.juanayala.kontaktLibraryManager/updates";
constexpr char kFeedUrl[] =
    "https://raw.githubusercontent.com/cloinse/klm/main/updates/"
    "appcast-windows.xml";
constexpr char kPublicKey[] =
    "IEM06s9BrwRuC4XtbnRQi6/hVNrTP+aN0naS8RdQNA8=";

template <typename Function>
bool LoadFunction(HMODULE module, const char* name, Function* function) {
  *function = reinterpret_cast<Function>(::GetProcAddress(module, name));
  return *function != nullptr;
}

std::wstring ExecutableDirectory() {
  wchar_t path[MAX_PATH] = {};
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) return {};
  std::wstring directory(path, length);
  const size_t separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return {};
  directory.resize(separator);
  return directory;
}

#define KLM_STRINGIFY_INNER(value) #value
#define KLM_STRINGIFY(value) KLM_STRINGIFY_INNER(value)
#define KLM_WIDEN_INNER(value) L##value
#define KLM_WIDEN(value) KLM_WIDEN_INNER(value)
#define KLM_DISPLAY_VERSION                                                   \
  KLM_STRINGIFY(FLUTTER_VERSION_MAJOR) "." KLM_STRINGIFY(                   \
      FLUTTER_VERSION_MINOR) "." KLM_STRINGIFY(FLUTTER_VERSION_PATCH)

}  // namespace

UpdateBridge* UpdateBridge::instance_ = nullptr;

UpdateBridge::UpdateBridge(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  configured_ = LoadWinSparkle();
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

UpdateBridge::~UpdateBridge() {
  channel_->SetMethodCallHandler(nullptr);
  if (configured_ && cleanup_ != nullptr) cleanup_();
  if (instance_ == this) instance_ = nullptr;
  if (module_ != nullptr) ::FreeLibrary(module_);
}

bool UpdateBridge::LoadWinSparkle() {
  const std::wstring directory = ExecutableDirectory();
  if (directory.empty()) return false;
  const std::wstring dll_path = directory + L"\\WinSparkle.dll";
  module_ = ::LoadLibraryExW(dll_path.c_str(), nullptr,
                             LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                                 LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (module_ == nullptr) return false;

  SetStringFunction set_appcast_url = nullptr;
  SetPublicKeyFunction set_public_key = nullptr;
  SetWideDetailsFunction set_app_details = nullptr;
  SetWideStringFunction set_build_version = nullptr;
  SetIntegerFunction set_automatic_checks = nullptr;
  SetCanShutdownFunction set_can_shutdown = nullptr;
  SetShutdownFunction set_shutdown = nullptr;
  VoidFunction init = nullptr;

  const bool loaded =
      LoadFunction(module_, "win_sparkle_set_appcast_url", &set_appcast_url) &&
      LoadFunction(module_, "win_sparkle_set_eddsa_public_key",
                   &set_public_key) &&
      LoadFunction(module_, "win_sparkle_set_app_details", &set_app_details) &&
      LoadFunction(module_, "win_sparkle_set_app_build_version",
                   &set_build_version) &&
      LoadFunction(module_, "win_sparkle_set_automatic_check_for_updates",
                   &set_automatic_checks) &&
      LoadFunction(module_, "win_sparkle_set_can_shutdown_callback",
                   &set_can_shutdown) &&
      LoadFunction(module_, "win_sparkle_set_shutdown_request_callback",
                   &set_shutdown) &&
      LoadFunction(module_, "win_sparkle_check_update_with_ui_and_install",
                   &check_update_with_ui_and_install_) &&
      LoadFunction(module_, "win_sparkle_cleanup", &cleanup_) &&
      LoadFunction(module_, "win_sparkle_init", &init);
  if (!loaded || set_public_key(kPublicKey) != 1) return false;

  set_appcast_url(kFeedUrl);
  set_app_details(L"Juan Ayala", L"Kontakt Library Manager",
                  KLM_WIDEN(KLM_DISPLAY_VERSION));
  set_build_version(KLM_WIDEN(KLM_STRINGIFY(FLUTTER_VERSION_BUILD)));
  set_automatic_checks(0);
  instance_ = this;
  set_can_shutdown(&UpdateBridge::CanShutdown);
  set_shutdown(&UpdateBridge::RequestShutdown);
  init();
  return true;
}

void UpdateBridge::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "getInfo") {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("currentVersion")] =
        flutter::EncodableValue(KLM_DISPLAY_VERSION);
    payload[flutter::EncodableValue("currentBuild")] =
        flutter::EncodableValue(KLM_STRINGIFY(FLUTTER_VERSION_BUILD));
    payload[flutter::EncodableValue("configured")] =
        flutter::EncodableValue(configured_);
    result->Success(flutter::EncodableValue(payload));
    return;
  }
  if (call.method_name() == "installUpdate") {
    if (!configured_ || check_update_with_ui_and_install_ == nullptr) {
      result->Error("updater_not_configured",
                    "The update service is not configured.");
      return;
    }
    check_update_with_ui_and_install_();
    result->Success();
    return;
  }
  result->NotImplemented();
}

int __cdecl UpdateBridge::CanShutdown() {
  return instance_ != nullptr && ::IsWindow(instance_->window_) ? TRUE : FALSE;
}

void __cdecl UpdateBridge::RequestShutdown() {
  if (instance_ != nullptr && ::IsWindow(instance_->window_)) {
    ::PostMessageW(instance_->window_, WM_CLOSE, 0, 0);
  }
}
