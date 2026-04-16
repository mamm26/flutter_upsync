#include "include/upsync/upsync_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "upsync_plugin.h"

void UpsyncPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  UpsyncPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
