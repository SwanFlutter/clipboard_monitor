#ifndef FLUTTER_PLUGIN_CLIPBOARD_MONITOR_PLUGIN_H_
#define FLUTTER_PLUGIN_CLIPBOARD_MONITOR_PLUGIN_H_

#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <optional>
#include <string>

namespace clipboard_monitor {

// Reads CF_UNICODETEXT from the clipboard. Returns nullopt when the clipboard
// holds no text or is held by another process.
std::optional<std::wstring> ReadClipboardText(HWND owner);

// Writes text as CF_UNICODETEXT. Returns false when the clipboard is busy.
bool WriteClipboardText(HWND owner, const std::wstring& text);

class ClipboardMonitorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit ClipboardMonitorPlugin(flutter::PluginRegistrarWindows* registrar);

  ~ClipboardMonitorPlugin() override;

  ClipboardMonitorPlugin(const ClipboardMonitorPlugin&) = delete;
  ClipboardMonitorPlugin& operator=(const ClipboardMonitorPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
};

}  // namespace clipboard_monitor

#endif  // FLUTTER_PLUGIN_CLIPBOARD_MONITOR_PLUGIN_H_
