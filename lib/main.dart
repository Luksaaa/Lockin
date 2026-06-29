import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const LockinApp());
}

class LockinApp extends StatelessWidget {
  const LockinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lockin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF070A0E),
        useMaterial3: true,
      ),
      home: const LockinHomePage(),
    );
  }
}

class LockinHomePage extends StatefulWidget {
  const LockinHomePage({super.key});

  @override
  State<LockinHomePage> createState() => _LockinHomePageState();
}

class _LockinHomePageState extends State<LockinHomePage> {
  static const _channel = MethodChannel('lockin/app_blocker');
  static const _usageLimitMs = 40 * 60 * 1000;
  bool _loading = true;
  bool _blockingActive = false;
  String _unlockText = '';
  List<AppInfo> _installedApps = const [];
  Set<String> _blockedPackages = {};
  Map<String, int> _usageByPackage = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadState(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('getState');
      final appsResult = await _channel.invokeListMethod<dynamic>(
        'getInstalledApps',
      );
      if (!mounted) return;

      final blocked = Set<String>.from(
        state?['blockedPackages'] as List? ?? const [],
      );
      final usage = <String, int>{};
      final rawUsage = state?['usageByPackage'] as Map?;
      rawUsage?.forEach(
        (key, value) => usage[key.toString()] = (value as num).toInt(),
      );

      setState(() {
        _loading = false;
        _blockingActive = state?['isBlockingActive'] == true;
        _unlockText = state?['unlockText']?.toString() ?? '';
        _blockedPackages = blocked;
        _usageByPackage = usage;
        _installedApps = (appsResult ?? const [])
            .map(
              (item) => AppInfo.fromMap(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(error.message ?? 'Ne mogu ucitati stanje aplikacije.');
    }
  }

  Future<void> _toggleBlocking() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'toggleBlocking',
      );
      final message = result?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await _loadState();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Akcija nije uspjela.');
      await _loadState();
    }
  }

  Future<void> _toggleApp(AppInfo app) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'toggleBlockedApp',
        {'packageName': app.packageName},
      );
      final message = result?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await _loadState();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Aplikacija nije promijenjena.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAppPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10151D),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Odaberi aplikacije',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zatvori',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    itemCount: _installedApps.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final app = _installedApps[index];
                      final selected = _blockedPackages.contains(
                        app.packageName,
                      );
                      return ListTile(
                        leading: AppIcon(app: app, size: 42),
                        title: Text(
                          app.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          app.packageName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? const Color(0xFF22C55E)
                              : Colors.white30,
                        ),
                        onTap: () => _toggleApp(app),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedApps = _installedApps
        .where((app) => _blockedPackages.contains(app.packageName))
        .toList();

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lockin',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '40 min unutar 4 sata',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Osvjezi',
                          onPressed: _loadState,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 92,
                      child: selectedApps.isEmpty
                          ? const Center(
                              child: Text(
                                'Ovdje su blokirane aplikacije',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: selectedApps.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, index) {
                                final app = selectedApps[index];
                                final usedMs =
                                    _usageByPackage[app.packageName] ?? 0;
                                final minutesLeft =
                                    ((_usageLimitMs - usedMs).clamp(
                                              0,
                                              _usageLimitMs,
                                            ) /
                                            60000)
                                        .floor();
                                return GestureDetector(
                                  onTap: () => _toggleApp(app),
                                  child: SizedBox(
                                    width: 72,
                                    child: Column(
                                      children: [
                                        AppIcon(app: app, size: 56),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${minutesLeft}m',
                                          style: TextStyle(
                                            color: minutesLeft > 0
                                                ? Colors.white54
                                                : const Color(0xFFEF4444),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          fixedSize: const Size(224, 224),
                          backgroundColor: _blockingActive
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                        onPressed: _toggleBlocking,
                        child: Text(
                          _blockingActive ? 'OFF' : 'ON',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _blockingActive
                          ? 'STATUS: BLOKIRANJE AKTIVNO'
                          : 'STATUS: UGASENO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _blockingActive
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF22C55E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _blockingActive && _unlockText.isNotEmpty
                          ? 'Otkljucavanje za: $_unlockText'
                          : '${selectedApps.length} odabrano',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0x73FFFFFF)),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _showAppPicker,
                      icon: const Icon(Icons.add),
                      label: const Text('Dodaj aplikacije'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({required this.app, required this.size, super.key});

  final AppInfo app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = app.iconBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: Colors.white10,
        child: bytes == null
            ? const Icon(Icons.apps)
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

class AppInfo {
  const AppInfo({
    required this.packageName,
    required this.label,
    required this.iconBytes,
  });

  final String packageName;
  final String label;
  final Uint8List? iconBytes;

  factory AppInfo.fromMap(Map<String, dynamic> map) {
    final icon = map['icon']?.toString();
    return AppInfo(
      packageName: map['packageName']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      iconBytes: icon == null || icon.isEmpty ? null : base64Decode(icon),
    );
  }
}
