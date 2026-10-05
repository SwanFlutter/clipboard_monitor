# clipboard_monitor

Watch the system clipboard and get an event whenever its **text** changes —
handy for auto-detecting copied download links. Pure Dart, no method channels,
three desktop platforms.

| Platform | Mechanism | Default interval |
| --- | --- | --- |
| Windows | Native plugin: hidden message-only window + `AddClipboardFormatListener`, `WM_CLIPBOARDUPDATE` pushed over an event channel | none (event driven) |
| macOS | `dart:ffi` → AppKit `NSPasteboard.changeCount` | 500 ms |
| Linux | `Process` poll of `wl-paste` / `xclip`, de-duplicated with an FNV-1a hash | 1 s |

Detection, de-duplication and the write loop guard live in one place
(`ClipboardMonitor`), so the observable behaviour is identical on every
platform.

Windows also ships `WindowsFfiClipboardBackend`, a polling
`GetClipboardSequenceNumber` implementation with no native dependency. It is
what `flutter test` uses to drive the real clipboard, and it can be passed to
`ClipboardMonitor.withBackend` if you prefer not to link the native plugin.

## Usage

```yaml
dependencies:
  clipboard_monitor: ^0.1.0
```

```dart
import 'package:clipboard_monitor/clipboard_monitor.dart';

final monitor = ClipboardMonitor(pollInterval: const Duration(milliseconds: 500));

if (!monitor.isSupported) {
  // Nothing to watch here (e.g. Wayland without wl-clipboard/xclip).
  // Not an error: textChanges is simply an empty stream.
}

monitor.textChanges.listen((text) {
  if (looksLikeDownloadUrl(text)) capture(text);   // already de-duplicated
});

await monitor.start();   // the current clipboard is the baseline, not an event
// ...
await monitor.stop();    // can be started again later
await monitor.readText();
await monitor.writeText('https://example.com/file.zip'); // emits no event
await monitor.dispose();
```

### API

- `ClipboardMonitor({Duration? pollInterval})`
- `Stream<String> get textChanges` — broadcast; emits the new text on each
  change, only when it differs from the previous emission, and never for text
  written through `writeText`.
- `Future<String?> readText()` / `Future<void> writeText(String text)`
- `Future<void> start()` / `Future<void> stop()` / `Future<void> dispose()`
- `bool get isSupported`, `bool get isRunning`
- `looksLikeDownloadUrl(String text)` — `http(s)` URL with a known file
  extension, a `?download`/`?filename`/content-disposition hint, or a
  `/download/` path segment.

## Platform notes

- **Windows**: the native plugin creates a message-only window (`HWND_MESSAGE`,
  never shown, no taskbar entry) and registers it with
  `AddClipboardFormatListener`, so changes are delivered as they happen and
  nothing runs while the clipboard is idle. The window exists only while
  `textChanges` has a listener. `OpenClipboard` can fail transiently while
  another app owns the clipboard; the read retries a few times and a missed
  change is picked up by the next notification.
- **macOS**: no clipboard-changed notification exists, so `changeCount` polling
  is the canonical approach. Text is read straight from `NSPasteboard`;
  Flutter's `Clipboard` is used as a fallback.
- **Linux**: needs `wl-clipboard` (`wl-paste` + `wl-copy`) on Wayland or `xclip`
  on X11. With neither installed, `isSupported` is `false` and `textChanges`
  stays empty — by design.

## Tests

```sh
flutter test          # logic + live clipboard checks on the host platform
```

The live group drives the real clipboard (via `WindowsFfiClipboardBackend`,
since `flutter test` does not link native code) and is skipped on other OSes, so
acceptance is verified per platform: three distinct copies → three events, one
repeat → one event, and a `writeText` from the host app → no event. The native
`WM_CLIPBOARDUPDATE` path is covered by channel contract tests plus a run of the
example app.

## Example app

`example/` shows start/stop, changing the poll interval, `readText`/`writeText`,
the loop guard (the "writeText" buttons change the clipboard but produce no
event), `isSupported`, and `looksLikeDownloadUrl` filtering.

```sh
cd example && flutter run -d windows   # or -d macos / linux
```
