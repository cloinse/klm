#ifndef RUNNER_REGISTRY_BRIDGE_H_
#define RUNNER_REGISTRY_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class RegistryBridge {
 public:
  explicit RegistryBridge(flutter::BinaryMessenger* messenger);
  ~RegistryBridge();

  RegistryBridge(const RegistryBridge&) = delete;
  RegistryBridge& operator=(const RegistryBridge&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_REGISTRY_BRIDGE_H_
