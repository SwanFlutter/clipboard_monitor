import 'dart:async';

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'download_url.dart' as url;
import 'platform_backend.dart';

/// Watches the system clipboard and emits its text whenever it changes.
///
/// * Windows: native plugin — a hidden message-only window registered as a
///   clipboard format listener pushes changes over an event channel.
/// * macOS: pure dart:ffi with AppKit NSPasteboard `changeCount` polling.
/// * Linux: polls `wl-paste` (Wayland) or `xclip` (X11).
///
/// Events are de-duplicated (only emitted when the text differs from the last
/// known text) and never emitted for writes made through [writeText].
class ClipboardMonitor {
  /// Creates a monitor. [pollInterval] is used by the macOS and Linux pollers;
  /// the Windows listener is event driven and ignores it.
  ClipboardMonitor({Duration? pollInterval})
      : this.withBackend(createPlatformBackend(pollInterval));

  /// Creates a monitor with a custom backend (useful for tests).
  @visibleForTesting
  ClipboardMonitor.withBackend(this._backend);

  final ClipboardBackend _backend;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _subscription;
  Future<void>? _starting;
  String? _lastText;
  int _writesInProgress = 0;
  bool _disposed = false;

  /// `false` when the clipboard can't be watched here. In that case [textChanges]
  /// is an empty stream; this is not an error.
  bool get isSupported => _backend.isSupported;

  /// Whether [start] has been called and [stop] hasn't.
  bool get isRunning => _subscription != null;

  /// Emits the new clipboard text on every (de-duplicated) change while
  /// running. Broadcast stream; listen before or after [start].
  Stream<String> get textChanges =>
      isSupported ? _controller.stream : const Stream<String>.empty();

  /// Starts watching. The text already on the clipboard is used as the
  /// baseline and is not emitted.
  Future<void> start() {
    if (_disposed || !isSupported || _subscription != null) {
      return Future<void>.value();
    }
    return _starting ??= _doStart().whenComplete(() => _starting = null);
  }

  Future<void> _doStart() async {
    _lastText = await _safeRead();
    if (_disposed || _subscription != null) return;
    _subscription = _backend.watch().listen(
      _onCandidate,
      onError: (Object e, StackTrace s) => _controller.addError(e, s),
    );
  }

  /// Stops watching. Can be restarted with [start].
  Future<void> stop() async {
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
  }

  /// Reads the current clipboard text (`null` if there is none).
  Future<String?> readText() => _backend.read();

  /// Writes [text] to the clipboard without triggering [textChanges].
  Future<void> writeText(String text) async {
    _writesInProgress++;
    try {
      await _backend.write(text);
      _lastText = text;
    } finally {
      _writesInProgress--;
    }
  }

  /// See [url.looksLikeDownloadUrl].
  static bool looksLikeDownloadUrl(String text) =>
      url.looksLikeDownloadUrl(text);

  /// Stops watching and closes [textChanges].
  Future<void> dispose() async {
    _disposed = true;
    await stop();
    _backend.dispose();
    await _controller.close();
  }

  void _onCandidate(String text) {
    if (_writesInProgress > 0) return; // loop guard
    if (text == _lastText) return; // de-duplicate
    _lastText = text;
    if (!_controller.isClosed) _controller.add(text);
  }

  Future<String?> _safeRead() async {
    try {
      return await _backend.read();
    } catch (_) {
      return null;
    }
  }
}
