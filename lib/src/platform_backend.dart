import 'dart:io' show Platform;

import 'backend.dart';
import 'linux_backend.dart';
import 'macos_backend.dart';
import 'windows_native_backend.dart';

ClipboardBackend createPlatformBackend(Duration? pollInterval) {
  if (Platform.isWindows) {
    // Event driven: [pollInterval] is unused here, the native listener pushes.
    return WindowsNativeClipboardBackend();
  }
  if (Platform.isMacOS) {
    return MacOSClipboardBackend(pollInterval ?? const Duration(milliseconds: 500));
  }
  if (Platform.isLinux) {
    return LinuxClipboardBackend(pollInterval ?? const Duration(seconds: 1));
  }
  return UnsupportedClipboardBackend();
}
