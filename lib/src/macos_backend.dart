import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'backend.dart';

typedef _ObjcLookupC = Pointer<Void> Function(Pointer<Utf8>);
typedef _MsgSendPtrC = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendLongC = Int64 Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendLongDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _MsgSendWithArgC = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _ObjcRetainC = Pointer<Void> Function(Pointer<Void>);
typedef _ObjcRetainDart = Pointer<Void> Function(Pointer<Void>);

/// macOS clipboard backend implemented purely using `dart:ffi`
/// and the native Objective-C AppKit runtime (NSPasteboard).
class MacOSClipboardBackend implements ClipboardBackend {
  MacOSClipboardBackend(this.interval) : _pasteboard = _Pasteboard.tryCreate();

  final Duration interval;
  final _Pasteboard? _pasteboard;
  int _lastChangeCount = -1;
  Timer? _timer;

  @override
  bool get isSupported => _pasteboard != null;

  @override
  Stream<String> watch() {
    final pb = _pasteboard;
    if (pb == null) return const Stream<String>.empty();

    var busy = false;
    late final StreamController<String> controller;

    controller = StreamController<String>(
      onListen: () {
        _lastChangeCount = pb.changeCount();
        _timer = Timer.periodic(interval, (_) async {
          if (busy) return;
          final count = pb.changeCount();
          if (count == _lastChangeCount) return;
          _lastChangeCount = count;
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
    final pb = _pasteboard;
    if (pb != null) {
      final text = pb.readText();
      if (text != null) return text;
    }
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    final pb = _pasteboard;
    if (pb != null) {
      pb.writeText(text);
      _lastChangeCount = pb.changeCount();
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
  }
}

class _Pasteboard {
  _Pasteboard._(
    this._msgSendLong,
    this._msgSendWithArg,
    this._pasteboard,
    this._selChangeCount,
    this._selStringForType,
    this._selClearContents,
    this._selSetStringForType,
    this._nsStringPboardType,
    this._nsStringToUtf8,
    this._nsStringClass,
    this._selStringWithUtf8,
  );

  final _MsgSendLongDart _msgSendLong;
  final _MsgSendWithArgC _msgSendWithArg;
  final Pointer<Void> _pasteboard;
  final Pointer<Void> _selChangeCount;
  final Pointer<Void> _selStringForType;
  final Pointer<Void> _selClearContents;
  final Pointer<Void> _selSetStringForType;
  final Pointer<Void> _nsStringPboardType;
  final Pointer<Utf8> Function(Pointer<Void>) _nsStringToUtf8;
  final Pointer<Void> _nsStringClass;
  final Pointer<Void> _selStringWithUtf8;

  static _Pasteboard? tryCreate() {
    if (!Platform.isMacOS) return null;
    try {
      DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');
      final objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
      final getClass =
          objc.lookupFunction<_ObjcLookupC, _ObjcLookupC>('objc_getClass');
      final selRegister =
          objc.lookupFunction<_ObjcLookupC, _ObjcLookupC>('sel_registerName');
      final msgSendPtr =
          objc.lookupFunction<_MsgSendPtrC, _MsgSendPtrC>('objc_msgSend');
      final msgSendLong =
          objc.lookupFunction<_MsgSendLongC, _MsgSendLongDart>('objc_msgSend');
      final msgSendWithArg =
          objc.lookupFunction<_MsgSendWithArgC, _MsgSendWithArgC>('objc_msgSend');
      // generalPasteboard/stringWithUTF8String: return autoreleased objects; they
      // are kept for the process lifetime, so they must be retained here.
      final objcRetain =
          objc.lookupFunction<_ObjcRetainC, _ObjcRetainDart>('objc_retain');

      final utf8StringSel = selRegister('UTF8String'.toNativeUtf8());
      Pointer<Utf8> nsStringToUtf8(Pointer<Void> ptr) =>
          msgSendPtr(ptr, utf8StringSel).cast<Utf8>();

      return using((arena) {
        final cls = getClass('NSPasteboard'.toNativeUtf8(allocator: arena));
        final selGeneral =
            selRegister('generalPasteboard'.toNativeUtf8(allocator: arena));
        final selChangeCount =
            selRegister('changeCount'.toNativeUtf8(allocator: arena));
        final selStringForType =
            selRegister('stringForType:'.toNativeUtf8(allocator: arena));
        final selClearContents =
            selRegister('clearContents'.toNativeUtf8(allocator: arena));
        final selSetStringForType =
            selRegister('setString:forType:'.toNativeUtf8(allocator: arena));

        final nsStringCls =
            getClass('NSString'.toNativeUtf8(allocator: arena));
        final selStringWithUtf8 =
            selRegister('stringWithUTF8String:'.toNativeUtf8(allocator: arena));

        final nsStringPboardType = objcRetain(msgSendWithArg(
          nsStringCls,
          selStringWithUtf8,
          'public.utf8-plain-text'.toNativeUtf8(allocator: arena).cast<Void>(),
        ));

        if (cls == nullptr) return null;
        final pb = msgSendPtr(cls, selGeneral);
        if (pb == nullptr) return null;

        return _Pasteboard._(
          msgSendLong,
          msgSendWithArg,
          objcRetain(pb),
          selChangeCount,
          selStringForType,
          selClearContents,
          selSetStringForType,
          nsStringPboardType,
          nsStringToUtf8,
          nsStringCls,
          selStringWithUtf8,
        );
      });
    } catch (_) {
      return null;
    }
  }

  int changeCount() => _msgSendLong(_pasteboard, _selChangeCount);

  String? readText() {
    try {
      final strObj = _msgSendWithArg(_pasteboard, _selStringForType, _nsStringPboardType);
      if (strObj == nullptr) return null;
      final cStr = _nsStringToUtf8(strObj);
      return cStr == nullptr ? null : cStr.toDartString();
    } catch (_) {
      return null;
    }
  }

  void writeText(String text) {
    try {
      using((arena) {
        final textUtf8 = text.toNativeUtf8(allocator: arena);
        final nsStr = _msgSendWithArg(
          _nsStringClass,
          _selStringWithUtf8,
          textUtf8.cast<Void>(),
        );
        _msgSendLong(_pasteboard, _selClearContents);
        _msgSendWithArg(_pasteboard, _selSetStringForType, nsStr);
      });
    } catch (_) {
      // fallback
    }
  }
}
