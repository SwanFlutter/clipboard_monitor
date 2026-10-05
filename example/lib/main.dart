import 'dart:async';

import 'package:clipboard_monitor/clipboard_monitor.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ClipboardMonitorExampleApp());

class ClipboardMonitorExampleApp extends StatelessWidget {
  const ClipboardMonitorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clipboard Monitor example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const MonitorPage(),
    );
  }
}

class CapturedChange {
  CapturedChange(this.text, this.at) : isDownload = looksLikeDownloadUrl(text);

  final String text;
  final DateTime at;
  final bool isDownload;
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const Map<String, Duration> _intervals = {
    '250 ms': Duration(milliseconds: 250),
    '500 ms': Duration(milliseconds: 500),
    '1 s': Duration(seconds: 1),
    '2 s': Duration(seconds: 2),
  };

  // The poll interval is a constructor argument, so changing it means building
  // a new ClipboardMonitor (see [_restartWith]).
  Duration _interval = const Duration(milliseconds: 500);
  ClipboardMonitor _monitor =
      ClipboardMonitor(pollInterval: const Duration(milliseconds: 500));
  StreamSubscription<String>? _subscription;

  bool _running = false;
  bool _onlyDownloadUrls = false;
  final List<CapturedChange> _changes = [];
  int _appWrites = 0;
  String? _snapshot;

  @override
  void initState() {
    super.initState();
    _listen();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _monitor.dispose();
    super.dispose();
  }

  void _listen() {
    _subscription = _monitor.textChanges.listen((text) {
      setState(() => _changes.insert(0, CapturedChange(text, DateTime.now())));
    });
  }

  Future<void> _start() async {
    await _monitor.start();
    if (mounted) setState(() => _running = _monitor.isSupported);
  }

  Future<void> _stop() async {
    await _monitor.stop();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _restartWith(Duration interval) async {
    await _subscription?.cancel();
    await _monitor.dispose();
    if (!mounted) return;
    setState(() {
      _interval = interval;
      _monitor = ClipboardMonitor(pollInterval: interval);
      _running = false;
    });
    _listen();
    await _start();
  }

  Future<void> _readClipboard() async {
    final text = await _monitor.readText();
    if (mounted) setState(() => _snapshot = text);
  }

  /// Writes through the plugin: the clipboard really changes, but [textChanges]
  /// stays silent because of the loop guard.
  Future<void> _writeFromApp(String text) async {
    await _monitor.writeText(text);
    if (mounted) setState(() => _appWrites++);
  }

  List<CapturedChange> get _visible => _onlyDownloadUrls
      ? _changes.where((c) => c.isDownload).toList(growable: false)
      : _changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloads = _changes.where((c) => c.isDownload).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard Monitor'),
        actions: [
          IconButton(
            tooltip: 'Read clipboard now (readText)',
            onPressed: _readClipboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      avatar: Icon(
                        _monitor.isSupported
                            ? Icons.check_circle
                            : Icons.do_not_disturb_on,
                        size: 18,
                        color: _monitor.isSupported ? Colors.green : Colors.orange,
                      ),
                      label: Text(
                          _monitor.isSupported ? 'isSupported: true' : 'isSupported: false'),
                    ),
                    const SizedBox(width: 8),
                    Chip(label: Text(_running ? 'running' : 'stopped')),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _intervals.entries
                          .firstWhere((e) => e.value == _interval)
                          .key,
                      items: _intervals.keys
                          .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                          .toList(),
                      onChanged: (k) =>
                          k == null ? null : _restartWith(_intervals[k]!),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('events: ${_changes.length}   ·   download links: $downloads'
                    '   ·   app writes (guarded): $_appWrites'),
                const SizedBox(height: 4),
                Text(
                  _snapshot == null
                      ? 'readText(): not called yet'
                      : 'readText(): $_snapshot',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? _stop : _start,
                  icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                  label: Text(_running ? 'Stop' : 'Start'),
                ),
                OutlinedButton(
                  onPressed: () => _writeFromApp(
                      'https://cdn.example.org/releases/build-${DateTime.now().microsecondsSinceEpoch % 100000}.zip'),
                  child: const Text('writeText: sample URL'),
                ),
                TextButton.icon(
                  onPressed: () => setState(
                      () => _onlyDownloadUrls = !_onlyDownloadUrls),
                  icon: Icon(_onlyDownloadUrls
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined),
                  label: const Text('only download links'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _changes.clear();
                    _appWrites = 0;
                    _snapshot = null;
                  }),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          if (!_monitor.isSupported)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.tertiaryContainer,
              child: const Text(
                'This environment has no clipboard watcher (Linux without '
                'wl-clipboard/xclip, or Wayland without them). textChanges is an '
                'empty stream and this is not an error.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _visible.isEmpty
                ? const _EmptyHint()
                : ListView.separated(
                    itemCount: _visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final change = _visible[index];
                      return ListTile(
                        leading: Icon(
                          change.isDownload
                              ? Icons.download
                              : Icons.content_copy,
                          color: change.isDownload
                              ? theme.colorScheme.primary
                              : null,
                        ),
                        title: Text(change.text,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${_time(change.at)}'
                          '${change.isDownload ? '  ·  looksLikeDownloadUrl == true' : ''}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Re-copy without triggering an event',
                          icon: const Icon(Icons.reply),
                          onPressed: () => _writeFromApp(change.text),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_search, size: 40),
            SizedBox(height: 12),
            Text('Copy text in any app to see events here.\n'
                'Writes made from this window stay silent (loop guard).',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _time(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}:'
    '${dt.second.toString().padLeft(2, '0')}.'
    '${dt.millisecond.toString().padLeft(3, '0')}';
