#include "include/clipboard_monitor/clipboard_monitor_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "clipboard_monitor_plugin.h"

void ClipboardMonitorPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  clipboard_monitor::ClipboardMonitorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
