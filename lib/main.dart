import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'duration_format.dart';

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

  Future<bool> _toggleApp(AppInfo app) async {
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
      return true;
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Aplikacija nije promijenjena.');
      return false;
    }
  }

  Future<void> _setUsageLimitMinutes(int minutes) async {
    final nextMinutes = minutes.clamp(_minLimitMinutes, _maxLimitMinutes);
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

  Future<void> _setUsageWindowHours(int hours) async {
    final nextHours = hours.clamp(3, 24);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setUsageWindowHours',
        {'hours': nextHours},
      );
      final message = result?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        _showMessage(message);
      }
      await _loadState();
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'Sati nisu promijenjeni.');
    }
  }

  int get _minLimitMinutes => _isTestMode ? 1 : 5;

  int get _maxLimitMinutes {
    if (_isTestMode) return 60;
    return (((_usageWindowMs / 60000) * 0.4).floor()).clamp(
      _minLimitMinutes,
      24 * 60,
    );
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
    var pickerSelectedPackages = Set<String>.from(_blockedPackages);
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
            return StatefulBuilder(
              builder: (context, setPickerState) {
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
                          final selected = pickerSelectedPackages.contains(
                            app.packageName,
                          );
                          return ListTile(
                            selected: selected,
                            selectedTileColor: const Color(0x1422C55E),
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
                                  ? const Color(0xFFD7BE7D)
                                  : Colors.white30,
                            ),
                            onTap: () async {
                              setPickerState(() {
                                if (selected) {
                                  pickerSelectedPackages.remove(
                                    app.packageName,
                                  );
                                } else {
                                  pickerSelectedPackages.add(app.packageName);
                                }
                              });
                              await _toggleApp(app);
                              setPickerState(() {
                                pickerSelectedPackages = Set<String>.from(
                                  _blockedPackages,
                                );
                              });
                            },
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedApps = _installedApps
        .where((app) => _blockedPackages.contains(app.packageName))
        .toList();
    final usageLimitMinutes = (_usageLimitMs / 60000).round();
    final usageWindowHours = (_usageWindowMs / 3600000).round().clamp(3, 24);

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
                                hours: usageWindowHours,
                                minMinutes: _minLimitMinutes,
                                maxMinutes: _maxLimitMinutes,
                                enabled: !_blockingActive,
                                testMode: _isTestMode,
                                onMinutesChanged: _setUsageLimitMinutes,
                                onHoursChanged: _setUsageWindowHours,
                                onTestModeChanged: _setTestMode,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _showAppPicker,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFD7BE7D,
                                        ),
                                        foregroundColor: const Color(
                                          0xFF0B0D10,
                                        ),
                                        minimumSize: const Size.fromHeight(54),
                                      ),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Dodaj aplikacije'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton.outlined(
                                    tooltip: 'Osvjezi aplikacije',
                                    onPressed: _loadState,
                                    style: IconButton.styleFrom(
                                      foregroundColor: const Color(0xFFF1E2BE),
                                      side: const BorderSide(
                                        color: Color(0xFF6D5A32),
                                      ),
                                      minimumSize: const Size(54, 54),
                                    ),
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
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
    required this.hours,
    required this.minMinutes,
    required this.maxMinutes,
    required this.enabled,
    required this.testMode,
    required this.onMinutesChanged,
    required this.onHoursChanged,
    required this.onTestModeChanged,
    super.key,
  });

  final int minutes;
  final int hours;
  final int minMinutes;
  final int maxMinutes;
  final bool enabled;
  final bool testMode;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<int> onHoursChanged;
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
          StepperRow(
            label: 'Minute',
            value: '$minutes min',
            detail: testMode
                ? 'test raspon 1-60 min'
                : 'raspon ${formatDurationLabel(minMinutes)}-${formatDurationLabel(maxMinutes)}',
            enabled: enabled,
            foreground: foreground,
            onDecrease: () => onMinutesChanged(minutes - (testMode ? 1 : 5)),
            onIncrease: () => onMinutesChanged(minutes + (testMode ? 1 : 5)),
          ),
          const Divider(height: 18, color: Color(0x336D5A32)),
          StepperRow(
            label: 'Sati',
            value: testMode ? '1 min' : '$hours h',
            detail: testMode ? 'testni prozor' : 'prozor koristenja',
            enabled: enabled && !testMode,
            foreground: foreground,
            onDecrease: () => onHoursChanged(hours - 1),
            onIncrease: () => onHoursChanged(hours + 1),
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

class StepperRow extends StatelessWidget {
  const StepperRow({
    required this.label,
    required this.value,
    required this.detail,
    required this.enabled,
    required this.foreground,
    required this.onDecrease,
    required this.onIncrease,
    super.key,
  });

  final String label;
  final String value;
  final String detail;
  final bool enabled;
  final Color foreground;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LimitIconButton(
          tooltip: 'Smanji $label',
          icon: Icons.remove,
          onPressed: enabled ? onDecrease : null,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        _LimitIconButton(
          tooltip: 'Povecaj $label',
          icon: Icons.add,
          onPressed: enabled ? onIncrease : null,
        ),
      ],
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
