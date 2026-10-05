import 'dart:async';

/// Platform mechanism used by [ClipboardMonitor]. One implementation per OS.
///
/// Backends only report *candidate* texts; de-duplication and the loop guard
/// are handled centrally by `ClipboardMonitor`.
abstract class ClipboardBackend {
  /// Whether clipboard watching works in the current environment.
  bool get isSupported;

  /// Starts watching when listened to and stops when the subscription is
  /// cancelled. Emits the current clipboard text after each detected change.
  Stream<String> watch();

  /// Reads the current clipboard text, or `null` if it holds no text.
  Future<String?> read();

  /// Writes [text] to the clipboard. Backends must update their internal
  /// baseline so this write is not reported by [watch].
  Future<void> write(String text);

  /// Disposes internal resources/timers if any.
  void dispose() {}
}

/// Used on unsupported platforms / environments.
class UnsupportedClipboardBackend implements ClipboardBackend {
  @override
  bool get isSupported => false;
  @override
  Stream<String> watch() => const Stream<String>.empty();
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String text) async {}
  @override
  void dispose() {}
}
