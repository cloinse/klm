#ifndef RUNNER_UPDATE_BRIDGE_H_
#define RUNNER_UPDATE_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class UpdateBridge {
 public:
  UpdateBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~UpdateBridge();

  UpdateBridge(const UpdateBridge&) = delete;
  UpdateBridge& operator=(const UpdateBridge&) = delete;

 private:
  using VoidFunction = void(__cdecl*)();
  using SetStringFunction = void(__cdecl*)(const char*);
  using SetWideDetailsFunction =
      void(__cdecl*)(const wchar_t*, const wchar_t*, const wchar_t*);
  using SetWideStringFunction = void(__cdecl*)(const wchar_t*);
  using SetIntegerFunction = void(__cdecl*)(int);
  using SetPublicKeyFunction = int(__cdecl*)(const char*);
  using CanShutdownCallback = int(__cdecl*)();
  using ShutdownCallback = void(__cdecl*)();
  using SetCanShutdownFunction = void(__cdecl*)(CanShutdownCallback);
  using SetShutdownFunction = void(__cdecl*)(ShutdownCallback);

  bool LoadWinSparkle();
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  static int __cdecl CanShutdown();
  static void __cdecl RequestShutdown();

  static UpdateBridge* instance_;

  HWND window_ = nullptr;
  HMODULE module_ = nullptr;
  bool configured_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  VoidFunction cleanup_ = nullptr;
  VoidFunction check_update_with_ui_ = nullptr;
};

#endif  // RUNNER_UPDATE_BRIDGE_H_
