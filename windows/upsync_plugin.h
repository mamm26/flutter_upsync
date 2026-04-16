#ifndef FLUTTER_PLUGIN_UPSYNC_PLUGIN_H_
#define FLUTTER_PLUGIN_UPSYNC_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

class UpsyncPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  UpsyncPlugin();
  ~UpsyncPlugin() override;

  UpsyncPlugin(const UpsyncPlugin&) = delete;
  UpsyncPlugin& operator=(const UpsyncPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif  // FLUTTER_PLUGIN_UPSYNC_PLUGIN_H_
