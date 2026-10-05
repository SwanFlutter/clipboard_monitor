import 'dart:async';
import 'dart:io';

import 'package:clipboard_monitor/clipboard_monitor.dart';
import 'package:clipboard_monitor/src/linux_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backend driven by the test: [emit] pushes a candidate text as if the
/// platform had detected a clipboard change.
class FakeBackend implements ClipboardBackend {
  FakeBackend({this.supported = true});

  final bool supported;
  final _source = StreamController<String>.broadcast();
  final writes = <String>[];
  String? content;

  void emit(String text) => _source.add(text);

  @override
  bool get isSupported => supported;

  @override
  Stream<String> watch() => _source.stream;

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String text) async {
    content = text;
    writes.add(text);
    // A real platform would now report this text as a change.
    emit(text);
  }

  @override
  void dispose() {}
}

Future<void> pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('textChanges', () {
    late FakeBackend backend;
    late ClipboardMonitor monitor;
    late List<String> events;
    late StreamSubscription<String> sub;

    setUp(() {
      backend = FakeBackend();
      monitor = ClipboardMonitor.withBackend(backend);
      events = [];
      sub = monitor.textChanges.listen(events.add);
    });

    tearDown(() async {
      await sub.cancel();
      await monitor.dispose();
    });

    test('emits one event per distinct change, in order', () async {
      await monitor.start();
      backend
        ..emit('https://a.com/x.zip')
        ..emit('https://b.com/y.pdf')
        ..emit('https://c.com/z.dmg');
      await pump();

      expect(events, [
        'https://a.com/x.zip',
        'https://b.com/y.pdf',
        'https://c.com/z.dmg',
      ]);
    });

    test('de-duplicates: same text copied twice emits once', () async {
      await monitor.start();
      backend
        ..emit('https://a.com/x.zip')
        ..emit('https://a.com/x.zip');
      await pump();
      expect(events, ['https://a.com/x.zip']);
    });

    test('does not emit the text already on the clipboard at start', () async {
      backend.content = 'stale';
      await monitor.start();
      await pump();
      expect(events, isEmpty);

      backend.emit('fresh');
      await pump();
      expect(events, ['fresh']);
    });

    test('loop guard: no event while the host app writes', () async {
      await monitor.start();
      await monitor.writeText('written by app');
      await pump();

      expect(backend.writes, ['written by app']);
      expect(events, isEmpty);

      backend.emit('copied by user');
      await pump();
      expect(events, ['copied by user']);
    });

    test('stop() halts events, start() resumes', () async {
      await monitor.start();
      backend.emit('one');
      await pump();
      await monitor.stop();

      backend.emit('two');
      await pump();
      expect(events, ['one']);

      await monitor.start();
      backend.emit('three');
      await pump();
      expect(events, ['one', 'three']);
    });

    test('unsupported platform: isSupported false and empty stream', () async {
      final unsupported =
          ClipboardMonitor.withBackend(FakeBackend(supported: false));
      expect(unsupported.isSupported, isFalse);

      await unsupported.start();
      expect(await unsupported.textChanges.toList(), isEmpty);
      await unsupported.dispose();
    });

    test('forward errors from the backend to the stream', () async {
      final failing = _FailingBackend();
      final m = ClipboardMonitor.withBackend(failing);
      final errors = <Object>[];
      final s = m.textChanges.listen(null, onError: (Object e) => errors.add(e));
      await m.start();
      await pump();

      expect(errors, ['boom']);
      await s.cancel();
      await m.dispose();
    });
  });

  group('looksLikeDownloadUrl', () {
    test('accepts http(s) urls with a file extension', () {
      expect(ClipboardMonitor.looksLikeDownloadUrl('https://a.com/f.zip'), isTrue);
      expect(ClipboardMonitor.looksLikeDownloadUrl('http://a.com/f.tar.gz'), isTrue);
      expect(ClipboardMonitor.looksLikeDownloadUrl('https://a.com/f.PDF'), isTrue);
      expect(
          ClipboardMonitor.looksLikeDownloadUrl('https://a.com/d/x.apk?dl=1'), isTrue);
      expect(
          ClipboardMonitor.looksLikeDownloadUrl(
              'https://a.com/f?response-content-disposition=attachment'),
          isTrue);
    });

    test('rejects non-download and non-url text', () {
      expect(ClipboardMonitor.looksLikeDownloadUrl('https://a.com/page'), isFalse);
      expect(ClipboardMonitor.looksLikeDownloadUrl('ftp://a.com/f.zip'), isFalse);
      expect(ClipboardMonitor.looksLikeDownloadUrl('just some text'), isFalse);
      expect(ClipboardMonitor.looksLikeDownloadUrl(''), isFalse);
      expect(
          ClipboardMonitor.looksLikeDownloadUrl('https://a.com/f.zip\nhttps://b.com'),
          isFalse);
    });

    test('top-level helper is exported', () {
      expect(looksLikeDownloadUrl('https://a.com/f.mp4'), isTrue);
    });
  });

  group('Linux tool detection', () {
    // detectTool parses PATH with ':' and looks for `$PATH_DIR/<exe>`; that is
    // only meaningful on a POSIX host, so these cases run on Linux.
    final linuxOnly = !Platform.isLinux;
    final wayland = {'WAYLAND_DISPLAY': 'wayland-0', 'PATH': '/fake/bin'};
    final x11 = {'DISPLAY': ':0', 'PATH': '/fake/bin'};

    void withPath(List<String> tools, void Function() body) {
      final dir = Directory.systemTemp.createTempSync('cm_path');
      for (final t in tools) {
        File('${dir.path}/$t').writeAsStringSync('#!/bin/sh\n');
      }
      try {
        body();
      } finally {
        dir.deleteSync(recursive: true);
      }
    }

    test('prefers wl-clipboard under Wayland when both tools exist', () {
      withPath(['wl-paste', 'wl-copy', 'xclip'], () {
        expect(LinuxClipboardBackend.detectTool({...wayland, 'DISPLAY': ':0'}),
            LinuxClipboardTool.wlClipboard);
      });
    }, skip: linuxOnly);

    test('uses xclip under X11', () {
      withPath(['xclip'], () {
        expect(LinuxClipboardBackend.detectTool(x11), LinuxClipboardTool.xclip);
      });
    }, skip: linuxOnly);

    test('falls back to xclip under Wayland when wl-clipboard is absent', () {
      withPath(['xclip'], () {
        expect(LinuxClipboardBackend.detectTool({...wayland, 'DISPLAY': ':0'}),
            LinuxClipboardTool.xclip);
      });
    }, skip: linuxOnly);

    test('unsupported when no tool or no display', () {
      withPath(['xclip'], () {
        // No DISPLAY / WAYLAND_DISPLAY at all.
        expect(LinuxClipboardBackend.detectTool({}), LinuxClipboardTool.none);
        // Wayland session without wl-clipboard and without X11 tools.
        expect(LinuxClipboardBackend.detectTool(wayland), LinuxClipboardTool.none);
      });
      withPath(['wl-paste'], () {
        // wl-copy missing -> not usable for writeText.
        expect(LinuxClipboardBackend.detectTool(wayland), LinuxClipboardTool.none);
      });
    }, skip: linuxOnly);

    test('unsupported backend -> empty stream, isSupported false', () async {
      final b = LinuxClipboardBackend(const Duration(seconds: 1), environment: {});
      expect(b.isSupported, isFalse);
      expect(await b.watch().isEmpty, isTrue);
    });

    test('fnv1a64 is stable and distinguishes text', () {
      expect(fnv1a64('abc'), fnv1a64('abc'));
      expect(fnv1a64('abc') == fnv1a64('abd'), isFalse);
    });
  });

  group('Windows native backend', () {
    const channel = MethodChannel('clipboard_monitor/windows');

    test('readText/writeText go over the plugin method channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'readText' ? 'text from native' : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final backend = WindowsNativeClipboardBackend();
      expect(backend.isSupported, Platform.isWindows);
      expect(await backend.read(), 'text from native');
      await backend.write('hello');

      expect(calls.map((c) => c.method), ['readText', 'writeText']);
      expect(calls[1].arguments, {'text': 'hello'});
    });

    test('watch() forwards clipboard notifications', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const events = EventChannel('clipboard_monitor/windows/changes');
      final handler = MockStreamHandler.inline(
        onListen: (Object? _, MockStreamHandlerEventSink sink) =>
            sink.success('https://a.com/f.zip'),
      );
      messenger.setMockStreamHandler(events, handler);
      addTearDown(() => messenger.setMockStreamHandler(events, null));

      expect(await WindowsNativeClipboardBackend().watch().first,
          'https://a.com/f.zip');
    });
  });

  // Acceptance criteria run against the real clipboard. `flutter test` does not
  // link the Windows native plugin, so this drives the FFI backend, which reads
  // the same system clipboard. The native listener is exercised by the example
  // app (see README).
  group('Windows backend (live clipboard)', () {
    final url1 = 'https://example.com/files/app-setup.exe';
    final url2 = 'https://cdn.example.net/video.mp4';
    final url3 = 'https://files.example.org/archive.tar.gz?v=2';

    Future<void> copyExternally(String text) async {
      final single = text.replaceAll("'", "''");
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', "Set-Clipboard -Value '$single'"],
      );
      if (r.exitCode != 0) throw StateError('Set-Clipboard failed: ${r.stderr}');
    }

    Future<bool> waitFor(bool Function() condition,
        {Duration timeout = const Duration(seconds: 5)}) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (condition()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return condition();
    }

    late ClipboardMonitor monitor;
    late List<String> events;
    late StreamSubscription<String> sub;

    setUp(() async {
      monitor = ClipboardMonitor.withBackend(
          WindowsFfiClipboardBackend(const Duration(milliseconds: 100)));
      events = [];
      sub = monitor.textChanges.listen(events.add);
      await monitor.start();
    });

    tearDown(() async {
      await sub.cancel();
      await monitor.dispose();
    });

    test('three different urls -> exactly three events with the right text',
        () async {
      final urls = [url1, url2, url3];
      for (var i = 0; i < urls.length; i++) {
        await copyExternally(urls[i]);
        expect(await waitFor(() => events.length == i + 1), isTrue,
            reason: 'missing event #${i + 1} for ${urls[i]}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(events, urls);
    }, skip: !Platform.isWindows);

    test('same text copied twice -> one event', () async {
      await copyExternally(url1);
      await waitFor(() => events.isNotEmpty);
      await copyExternally(url1);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(events, [url1]);
    }, skip: !Platform.isWindows);

    test('host app write emits no event', () async {
      await monitor.writeText('written by the host app');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(events, isEmpty);
      expect(await monitor.readText(), 'written by the host app');

      await copyExternally(url2);
      expect(await waitFor(() => events.isNotEmpty), isTrue);
      expect(events, [url2]);
    }, skip: !Platform.isWindows);

    test('isSupported on a real Windows session', () {
      expect(monitor.isSupported, isTrue);
    }, skip: !Platform.isWindows);
  });
}

class _FailingBackend implements ClipboardBackend {
  @override
  bool get isSupported => true;

  @override
  Stream<String> watch() =>
      Stream<String>.error('boom').asBroadcastStream();

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String text) async {}

  @override
  void dispose() {}
}
