/// Watch the system clipboard for text changes on Windows, macOS and Linux.
library;

export 'src/clipboard_monitor.dart' show ClipboardMonitor;
export 'src/download_url.dart' show looksLikeDownloadUrl;
export 'src/backend.dart' show ClipboardBackend;
export 'src/registrar.dart' show ClipboardMonitorRegistrar;
export 'src/windows_native_backend.dart' show WindowsNativeClipboardBackend;
export 'src/windows_ffi_backend.dart' show WindowsFfiClipboardBackend;
