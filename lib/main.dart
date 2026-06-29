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
  bool _loading = true;
  bool _blockingActive = false;
  int _usageLimitMs = 40 * 60 * 1000;
  int _usageWindowMs = 4 * 60 * 60 * 1000;
  bool _isTestMode = false;
  String _unlockText = '';
  List<AppInfo> _installedApps = const [];
  Set<String> _blockedPackages = {};
  Map<String, int> _usageByPackage = {};
  Timer? _refreshTimer;
  OverlayEntry? _messageOverlay;

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
    _messageOverlay?.remove();
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
        _usageLimitMs =
            (state?['usageLimitMs'] as num?)?.toInt() ?? 40 * 60 * 1000;
        _usageWindowMs =
            (state?['usageWindowMs'] as num?)?.toInt() ?? 4 * 60 * 60 * 1000;
        _isTestMode = state?['isTestMode'] == true;
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

  Future<void> _setUsageLimitMinutes(int minutes) async {
    final nextMinutes = minutes.clamp(_isTestMode ? 1 : 5, 240);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setUsageLimit',
        {'minutes': nextMinutes},
      );
      final message = result?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await _loadState();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Limit nije promijenjen.');
    }
  }

  Future<void> _setTestMode(bool enabled) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setTestMode',
        {'enabled': enabled},
      );
      final message = result?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await _loadState();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Testni nacin nije promijenjen.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    _messageOverlay?.remove();
    _messageOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 14,
          left: 24,
          right: 24,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111315),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFC9A968)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF1E2BE),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_messageOverlay!);
    Future.delayed(const Duration(seconds: 3), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
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
    final usageLimitMinutes = (_usageLimitMs / 60000).round();
    final windowLabel = _usageWindowMs <= 60000
        ? 'test: 1 minuta'
        : 'unutar ${(_usageWindowMs / 3600000).round()} sata';

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: ArtDecoLine()),
                                  IconButton.filledTonal(
                                    tooltip: 'Osvjezi',
                                    onPressed: _loadState,
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF25301F),
                                      foregroundColor: const Color(0xFFF1E2BE),
                                    ),
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
                                          style: TextStyle(
                                            color: Colors.white54,
                                          ),
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
                                              _usageByPackage[app
                                                  .packageName] ??
                                              0;
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
                                                          : const Color(
                                                              0xFFEF4444,
                                                            ),
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
                                        ? const Color(0xFFB42323)
                                        : const Color(0xFF1E6B3B),
                                    side: const BorderSide(
                                      color: Color(0xFFC9A968),
                                      width: 2,
                                    ),
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
                                      : const Color(0xFFC9A968),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _blockingActive && _unlockText.isNotEmpty
                                    ? 'Otkljucavanje za: $_unlockText'
                                    : '${selectedApps.length} odabrano',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0x73FFFFFF),
                                ),
                              ),
                              const Spacer(),
                              TimeLimitControl(
                                minutes: usageLimitMinutes,
                                windowLabel: windowLabel,
                                enabled: !_blockingActive,
                                testMode: _isTestMode,
                                onChanged: _setUsageLimitMinutes,
                                onTestModeChanged: _setTestMode,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _showAppPicker,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFD7BE7D),
                                  foregroundColor: const Color(0xFF0B0D10),
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Dodaj aplikacije'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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

class TimeLimitControl extends StatelessWidget {
  const TimeLimitControl({
    required this.minutes,
    required this.windowLabel,
    required this.enabled,
    required this.testMode,
    required this.onChanged,
    required this.onTestModeChanged,
    super.key,
  });

  final int minutes;
  final String windowLabel;
  final bool enabled;
  final bool testMode;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool> onTestModeChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? const Color(0xFFF1E2BE) : Colors.white38;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101113),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF6D5A32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _LimitIconButton(
                tooltip: 'Smanji limit',
                icon: Icons.remove,
                onPressed: enabled
                    ? () => onChanged(minutes - (testMode ? 1 : 5))
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$minutes min',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      windowLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _LimitIconButton(
                tooltip: 'Povecaj limit',
                icon: Icons.add,
                onPressed: enabled
                    ? () => onChanged(minutes + (testMode ? 1 : 5))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  testMode ? 'Testni nacin ukljucen' : 'Normalni nacin',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
              Switch(
                value: testMode,
                onChanged: enabled ? onTestModeChanged : null,
                activeThumbColor: const Color(0xFFD7BE7D),
                activeTrackColor: const Color(0xFF4B3F25),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitIconButton extends StatelessWidget {
  const _LimitIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFFF1E2BE),
        disabledForegroundColor: Colors.white24,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(42, 42),
      ),
    );
  }
}

class ArtDecoLine extends StatelessWidget {
  const ArtDecoLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: const Color(0xFF6D5A32))),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFC9A968)),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFF6D5A32))),
      ],
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
