import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend.dart';

enum LinuxClipboardTool { wlClipboard, xclip, none }

/// Linux: polls the clipboard through a CLI tool and compares hashes.
///
/// * Wayland (`WAYLAND_DISPLAY` set): `wl-paste` / `wl-copy` (wl-clipboard).
///   Falls back to `xclip` if only XWayland tools are installed.
/// * X11 (`DISPLAY` set): `xclip -selection clipboard`.
/// * No tool available: [isSupported] is `false` and [watch] is empty.
class LinuxClipboardBackend implements ClipboardBackend {
  LinuxClipboardBackend(this.interval, {Map<String, String>? environment})
      : tool = detectTool(environment ?? Platform.environment);

  final Duration interval;
  final LinuxClipboardTool tool;
  int? _lastHash;
  Timer? _timer;

  @override
  bool get isSupported => tool != LinuxClipboardTool.none;

  static LinuxClipboardTool detectTool(Map<String, String> env) {
    final path = env['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
    bool has(String exe) => path
        .split(':')
        .where((d) => d.isNotEmpty)
        .any((d) => File('$d/$exe').existsSync());

    final wayland = (env['WAYLAND_DISPLAY'] ?? '').isNotEmpty ||
        env['XDG_SESSION_TYPE'] == 'wayland';
    final x11 = (env['DISPLAY'] ?? '').isNotEmpty;

    if (wayland && has('wl-paste') && has('wl-copy')) {
      return LinuxClipboardTool.wlClipboard;
    }
    if (x11 && has('xclip')) return LinuxClipboardTool.xclip;
    return LinuxClipboardTool.none;
  }

  List<String> get _readCmd => switch (tool) {
        LinuxClipboardTool.wlClipboard => ['wl-paste', '--no-newline', '--type', 'text'],
        LinuxClipboardTool.xclip => ['xclip', '-selection', 'clipboard', '-o', '-t', 'UTF8_STRING'],
        LinuxClipboardTool.none => const [],
      };

  List<String> get _writeCmd => switch (tool) {
        LinuxClipboardTool.wlClipboard => ['wl-copy', '--type', 'text/plain;charset=utf-8'],
        LinuxClipboardTool.xclip => ['xclip', '-selection', 'clipboard', '-i'],
        LinuxClipboardTool.none => const [],
      };

  @override
  Stream<String> watch() {
    if (!isSupported) return const Stream<String>.empty();
    var busy = false;
    late final StreamController<String> controller;

    Future<void> tick({bool emit = true}) async {
      if (busy) return;
      busy = true;
      try {
        final text = await read();
        if (text == null) return; // empty / non-text clipboard
        final h = fnv1a64(text);
        if (h == _lastHash) return;
        _lastHash = h;
        if (emit && !controller.isClosed) controller.add(text);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      } finally {
        busy = false;
      }
    }

    controller = StreamController<String>(
      onListen: () {
        tick(emit: false); // baseline
        _timer = Timer.periodic(interval, (_) => tick());
      },
      onCancel: () {
        _timer?.cancel();
        _timer = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<String?> read() async {
    if (!isSupported) return null;
    final cmd = _readCmd;
    final r = await Process.run(cmd.first, cmd.sublist(1),
            stdoutEncoding: utf8, stderrEncoding: utf8)
        .timeout(const Duration(seconds: 3));
    return r.exitCode == 0 ? r.stdout as String : null;
  }

  @override
  Future<void> write(String text) async {
    if (!isSupported) return;
    // Baseline first so a concurrent poll never reports our own write.
    _lastHash = fnv1a64(text);
    final cmd = _writeCmd;
    final p = await Process.start(cmd.first, cmd.sublist(1));
    p.stdin.add(utf8.encode(text));
    await p.stdin.close();
    // xclip / wl-copy fork into the background to own the selection; the
    // foreground process exits right away.
    await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
  }
}

/// 64-bit FNV-1a hash of the UTF-8 bytes of [s].
int fnv1a64(String s) {
  var hash = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    hash ^= b;
    hash *= 0x100000001b3;
  }
  return hash;
}
