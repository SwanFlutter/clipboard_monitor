/// No-op registrar so Flutter discovers the Dart-only plugin on desktop
/// platforms (macOS, Linux, Windows) when configured via `dartPluginClass`.
class ClipboardMonitorRegistrar {
  static void registerWith() {}
}
