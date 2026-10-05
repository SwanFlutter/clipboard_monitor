## 0.1.0

* Clipboard text-change monitoring for Windows, macOS and Linux behind one API.
* Windows: native plugin with a hidden message-only window and
  `AddClipboardFormatListener` (`WM_CLIPBOARDUPDATE`), delivered over an event
  channel — no polling while idle.
* macOS: `NSPasteboard.changeCount` polling through `dart:ffi`.
* Linux: `wl-paste`/`xclip` polling with FNV-1a de-duplication; unsupported
  environments report `isSupported == false` and an empty stream.
* De-duplicated `textChanges`, `readText`/`writeText`, `start`/`stop`, and a
  loop guard that keeps the host app's own writes silent.
* `looksLikeDownloadUrl` helper for copied download links.
