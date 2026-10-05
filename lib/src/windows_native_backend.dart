import 'dart:io';

import 'package:flutter/services.dart';

import 'backend.dart';
import 'windows_ffi_backend.dart';

/// Windows backend driven by the native plugin: a hidden message-only window
/// registered with `AddClipboardFormatListener` pushes `WM_CLIPBOARDUPDATE`
/// notifications over an [EventChannel], so nothing polls while the clipboard
/// is idle.
///
/// Needs the plugin's native half to be linked into the app. In a plain
/// `flutter test` run it is not, so tests that drive the real clipboard use
/// [WindowsFfiClipboardBackend] instead.
class WindowsNativeClipboardBackend implements ClipboardBackend {
  static const MethodChannel _method =
      MethodChannel('clipboard_monitor/windows');
  static const EventChannel _changes =
      EventChannel('clipboard_monitor/windows/changes');

  @override
  bool get isSupported => Platform.isWindows;

  @override
  Stream<String> watch() => _changes
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>();

  @override
  Future<String?> read() => _method.invokeMethod<String>('readText');

  @override
  Future<void> write(String text) =>
      _method.invokeMethod<void>('writeText', {'text': text});

  // Cancelling the subscription makes the native side drop its clipboard
  // format listener, so there is nothing to release here.
  @override
  void dispose() {}
}
