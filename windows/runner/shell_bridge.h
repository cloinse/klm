#ifndef RUNNER_SHELL_BRIDGE_H_
#define RUNNER_SHELL_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class ShellBridge {
 public:
  explicit ShellBridge(flutter::BinaryMessenger* messenger);
  ~ShellBridge();

  ShellBridge(const ShellBridge&) = delete;
  ShellBridge& operator=(const ShellBridge&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SHELL_BRIDGE_H_
