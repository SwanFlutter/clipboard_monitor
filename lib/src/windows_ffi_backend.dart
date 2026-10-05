import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'backend.dart';

typedef _GetClipboardSeqC = Uint32 Function();
typedef _GetClipboardSeqDart = int Function();

typedef _OpenClipboardC = Int32 Function(Pointer<Void>);
typedef _OpenClipboardDart = int Function(Pointer<Void>);

typedef _CloseClipboardC = Int32 Function();
typedef _CloseClipboardDart = int Function();

typedef _GetClipboardDataC = Pointer<Void> Function(Uint32);
typedef _GetClipboardDataDart = Pointer<Void> Function(int);

typedef _GlobalLockC = Pointer<Void> Function(Pointer<Void>);
typedef _GlobalLockDart = Pointer<Void> Function(Pointer<Void>);

typedef _GlobalUnlockC = Int32 Function(Pointer<Void>);
typedef _GlobalUnlockDart = int Function(Pointer<Void>);

typedef _EmptyClipboardC = Int32 Function();
typedef _EmptyClipboardDart = int Function();

typedef _SetClipboardDataC = Pointer<Void> Function(Uint32, Pointer<Void>);
typedef _SetClipboardDataDart = Pointer<Void> Function(int, Pointer<Void>);

typedef _GlobalAllocC = Pointer<Void> Function(Uint32, IntPtr);
typedef _GlobalAllocDart = Pointer<Void> Function(int, int);

/// Windows Clipboard Backend using pure `dart:ffi` with `user32.dll` and `kernel32.dll`.
/// Uses `GetClipboardSequenceNumber` for ultra-lightweight O(1) polling.
class WindowsFfiClipboardBackend implements ClipboardBackend {
  WindowsFfiClipboardBackend([this.interval = const Duration(milliseconds: 300)]) {
    if (Platform.isWindows) {
      _initFfi();
    }
  }

  final Duration interval;
  bool _initialized = false;
  int _lastSeq = 0;
  Timer? _timer;

  late final _GetClipboardSeqDart _getSeqNum;
  late final _OpenClipboardDart _openClipboard;
  late final _CloseClipboardDart _closeClipboard;
  late final _GetClipboardDataDart _getClipboardData;
  late final _EmptyClipboardDart _emptyClipboard;
  late final _SetClipboardDataDart _setClipboardData;
  late final _GlobalLockDart _globalLock;
  late final _GlobalUnlockDart _globalUnlock;
  late final _GlobalAllocDart _globalAlloc;

  void _initFfi() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      _getSeqNum = user32
          .lookupFunction<_GetClipboardSeqC, _GetClipboardSeqDart>('GetClipboardSequenceNumber');
      _openClipboard = user32
          .lookupFunction<_OpenClipboardC, _OpenClipboardDart>('OpenClipboard');
      _closeClipboard = user32
          .lookupFunction<_CloseClipboardC, _CloseClipboardDart>('CloseClipboard');
      _getClipboardData = user32
          .lookupFunction<_GetClipboardDataC, _GetClipboardDataDart>('GetClipboardData');
      _emptyClipboard = user32
          .lookupFunction<_EmptyClipboardC, _EmptyClipboardDart>('EmptyClipboard');
      _setClipboardData = user32
          .lookupFunction<_SetClipboardDataC, _SetClipboardDataDart>('SetClipboardData');

      _globalLock = kernel32
          .lookupFunction<_GlobalLockC, _GlobalLockDart>('GlobalLock');
      _globalUnlock = kernel32
          .lookupFunction<_GlobalUnlockC, _GlobalUnlockDart>('GlobalUnlock');
      _globalAlloc = kernel32
          .lookupFunction<_GlobalAllocC, _GlobalAllocDart>('GlobalAlloc');

      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  @override
  bool get isSupported => _initialized;

  @override
  Stream<String> watch() {
    if (!isSupported) return const Stream<String>.empty();
    late final StreamController<String> controller;
    var busy = false;

    controller = StreamController<String>(
      onListen: () {
        _lastSeq = _getSeqNum();
        _timer = Timer.periodic(interval, (_) async {
          if (busy) return;
          final seq = _getSeqNum();
          if (seq == _lastSeq || seq == 0) return;
          _lastSeq = seq;
          busy = true;

          try {
            final text = await read();
            if (text != null && !controller.isClosed) {
              controller.add(text);
            }
          } catch (e, s) {
            if (!controller.isClosed) controller.addError(e, s);
          } finally {
            busy = false;
          }
        });
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
    const cfUnicodeText = 13; // CF_UNICODETEXT

    if (_openClipboard(nullptr) == 0) return null;
    try {
      final handle = _getClipboardData(cfUnicodeText);
      if (handle == nullptr) return null;

      final ptr = _globalLock(handle);
      if (ptr == nullptr) return null;
      try {
        return ptr.cast<Utf16>().toDartString();
      } finally {
        _globalUnlock(handle);
      }
    } catch (_) {
      return null;
    } finally {
      _closeClipboard();
    }
  }

  @override
  Future<void> write(String text) async {
    if (!isSupported) return;
    const gmemMoveable = 0x0002;
    const cfUnicodeText = 13;

    final units = text.codeUnits;
    final bytesCount = (units.length + 1) * 2;

    if (_openClipboard(nullptr) == 0) return;
    try {
      _emptyClipboard();
      final hMem = _globalAlloc(gmemMoveable, bytesCount);
      if (hMem == nullptr) return;

      final pMem = _globalLock(hMem);
      if (pMem != nullptr) {
        final dest = pMem.cast<Uint16>();
        for (var i = 0; i < units.length; i++) {
          dest[i] = units[i];
        }
        dest[units.length] = 0; // null-terminated
        _globalUnlock(hMem);
        _setClipboardData(cfUnicodeText, hMem);
      }
      _lastSeq = _getSeqNum();
    } finally {
      _closeClipboard();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
  }
}
