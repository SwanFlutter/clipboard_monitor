#include "clipboard_monitor_plugin.h"

#include <windows.h>

#include <flutter/standard_method_codec.h>

#include <cstring>

namespace clipboard_monitor {
namespace {

// Defined since Windows Vista; spelled out so the plugin does not depend on the
// client project's _WIN32_WINNT setting.
#ifndef WM_CLIPBOARDUPDATE
#define WM_CLIPBOARDUPDATE (WM_DRAWCLIPBOARD + 1)
#endif

constexpr char kMethodChannelName[] = "clipboard_monitor/windows";
constexpr char kEventChannelName[] = "clipboard_monitor/windows/changes";
constexpr wchar_t kWindowClassName[] = L"clipboard_monitor_ClipboardWatcher";

// EncodableValue carries text as UTF-8 std::string, the clipboard as UTF-16.
std::string Utf8FromUtf16(const std::wstring& utf16) {
  if (utf16.empty()) return std::string();
  const int length = WideCharToMultiByte(
      CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()), nullptr, 0,
      nullptr, nullptr);
  std::string utf8(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()),
                      utf8.data(), length, nullptr, nullptr);
  return utf8;
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), length);
  return wide;
}

std::optional<std::wstring> ReadTextFromClipboard(HWND owner) {
  bool opened = false;
  for (int attempt = 0; attempt < 5 && !opened; ++attempt) {
    opened = OpenClipboard(owner) != FALSE;
    if (!opened) Sleep(10);
  }
  if (!opened) return std::nullopt;

  std::optional<std::wstring> text;
  HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (handle != nullptr) {
    const auto* chars = static_cast<const wchar_t*>(GlobalLock(handle));
    if (chars != nullptr) {
      text = std::wstring(chars);
      GlobalUnlock(handle);
    }
  }
  CloseClipboard();
  return text;
}

// Owns the hidden message window for as long as a Dart listener is active.
struct ClipboardStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
  ClipboardStreamHandler() = default;
  ~ClipboardStreamHandler() override { DetachWindow(); }

  ClipboardStreamHandler(const ClipboardStreamHandler&) = delete;
  ClipboardStreamHandler& operator=(const ClipboardStreamHandler&) = delete;

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override {
    if (window_ == nullptr && !AttachWindow()) {
      return std::make_unique<flutter::StreamHandlerError<flutter::EncodableValue>>(
          "watch_failed",
          "Could not create the hidden clipboard listener window.", nullptr);
    }
    sink_ = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue* arguments) override {
    sink_.reset();
    DetachWindow();
    return nullptr;
  }

 private:
  void DetachWindow() {
    if (window_ == nullptr) return;
    RemoveClipboardFormatListener(window_);
    SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
    DestroyWindow(window_);
    window_ = nullptr;
  }

  HWND window_ = nullptr;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  bool AttachWindow() {
    HINSTANCE instance = GetModuleHandle(nullptr);
    static const bool class_registered = [&instance] {
      WNDCLASSEXW window_class{};
      window_class.cbSize = sizeof(window_class);
      window_class.lpfnWndProc = &ClipboardStreamHandler::WndProc;
      window_class.hInstance = instance;
      window_class.lpszClassName = kWindowClassName;
      return RegisterClassExW(&window_class) != 0;
    }();
    if (!class_registered) return false;

    // HWND_MESSAGE makes this a message-only window: no taskbar entry, no
    // visibility, no painting.
    HWND window = CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, nullptr, instance, nullptr);
    if (window == nullptr) return false;

    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(this));
    if (AddClipboardFormatListener(window) == FALSE) {
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      DestroyWindow(window);
      return false;
    }
    window_ = window;
    return true;
  }

  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM w_param,
                                 LPARAM l_param) {
    if (message == WM_CLIPBOARDUPDATE) {
      auto* self = reinterpret_cast<ClipboardStreamHandler*>(
          GetWindowLongPtrW(window, GWLP_USERDATA));
      if (self != nullptr && self->sink_ != nullptr) {
        std::optional<std::wstring> text = ReadTextFromClipboard(window);
        if (text.has_value()) {
          self->sink_->Success(flutter::EncodableValue(Utf8FromUtf16(*text)));
        }
      }
      return 0;
    }
    return DefWindowProcW(window, message, w_param, l_param);
  }
};

}  // namespace

std::optional<std::wstring> ReadClipboardText(HWND owner) {
  return ReadTextFromClipboard(owner);
}

bool WriteClipboardText(HWND owner, const std::wstring& text) {
  if (OpenClipboard(owner) == FALSE) return false;

  const size_t byte_count = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, byte_count);
  if (memory == nullptr) {
    CloseClipboard();
    return false;
  }

  auto* destination = static_cast<wchar_t*>(GlobalLock(memory));
  if (destination == nullptr) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  std::memcpy(destination, text.c_str(), byte_count);
  GlobalUnlock(memory);

  if (EmptyClipboard() == FALSE ||
      SetClipboardData(CF_UNICODETEXT, memory) == nullptr) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  CloseClipboard();
  return true;
}

void ClipboardMonitorPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<ClipboardMonitorPlugin>(registrar));
}

ClipboardMonitorPlugin::ClipboardMonitorPlugin(
    flutter::PluginRegistrarWindows* registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kMethodChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kEventChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(std::make_unique<ClipboardStreamHandler>());
}

ClipboardMonitorPlugin::~ClipboardMonitorPlugin() {
  // The channels do not own their handlers, so unregister explicitly: that
  // releases the stream handler together with its hidden window.
  if (event_channel_) event_channel_->SetStreamHandler(nullptr);
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  event_channel_.reset();
  channel_.reset();
}

void ClipboardMonitorPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "readText") {
    std::optional<std::wstring> text = ReadClipboardText(nullptr);
    if (text.has_value()) {
      result->Success(flutter::EncodableValue(Utf8FromUtf16(*text)));
    } else {
      result->Success();
    }
    return;
  }

  if (method == "writeText") {
    const auto* arguments =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    const std::string* text = nullptr;
    if (arguments != nullptr) {
      auto it = arguments->find(flutter::EncodableValue("text"));
      if (it != arguments->end()) text = std::get_if<std::string>(&it->second);
    }
    if (text == nullptr) {
      result->Error("bad_args", "writeText expects {'text': String}.");
      return;
    }
    if (!WriteClipboardText(nullptr, Utf16FromUtf8(*text))) {
      result->Error("write_failed",
                    "The clipboard was busy or rejected the write.");
      return;
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace clipboard_monitor
