import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsSetupScreen extends StatefulWidget {
  final Widget child;
  const PermissionsSetupScreen({super.key, required this.child});

  @override
  State<PermissionsSetupScreen> createState() => _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends State<PermissionsSetupScreen> {
  bool _checking = true;
  bool _allGranted = false;

  final List<_PermItem> _items = const [
    _PermItem(
      permission: _PermType.batteryOptimization,
      icon: Icons.battery_charging_full,
      title: 'Unrestricted battery usage',
      description:
          'Allows the app to receive calls and messages when it is closed. '
          'Without this, Android may block incoming calls.',
    ),
    _PermItem(
      permission: _PermType.displayOverOtherApps,
      icon: Icons.picture_in_picture,
      title: 'Display over other apps',
      description:
          'Allows the incoming call screen to appear on your lock screen '
          'so you never miss a call.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkAll();
  }

  Future<void> _checkAll() async {
    if (!Platform.isAndroid) {
      if (mounted)
        setState(() {
          _checking = false;
          _allGranted = true;
        });
      return;
    }
    final battOk = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlayOk = await Permission.systemAlertWindow.isGranted;
    if (mounted) {
      setState(() {
        _checking = false;
        _allGranted = battOk && overlayOk;
      });
    }
  }

  Future<void> _requestPermission(_PermType type) async {
    switch (type) {
      case _PermType.batteryOptimization:
        await Permission.ignoreBatteryOptimizations.request();
        break;
      case _PermType.displayOverOtherApps:
        await Permission.systemAlertWindow.request();
        break;
    }
    await _checkAll();
  }

  Future<bool> _isGranted(_PermType type) async {
    switch (type) {
      case _PermType.batteryOptimization:
        return Permission.ignoreBatteryOptimizations.isGranted;
      case _PermType.displayOverOtherApps:
        return Permission.systemAlertWindow.isGranted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();
    if (_allGranted) return widget.child;
    return _PermissionSetupPage(
      items: _items,
      isGranted: _isGranted,
      onRequest: _requestPermission,
      onContinue: () {
        if (mounted) setState(() => _allGranted = true);
      },
    );
  }
}

class _PermissionSetupPage extends StatefulWidget {
  final List<_PermItem> items;
  final Future<bool> Function(_PermType) isGranted;
  final Future<void> Function(_PermType) onRequest;
  final VoidCallback onContinue;

  const _PermissionSetupPage({
    required this.items,
    required this.isGranted,
    required this.onRequest,
    required this.onContinue,
  });

  @override
  State<_PermissionSetupPage> createState() => _PermissionSetupPageState();
}

class _PermissionSetupPageState extends State<_PermissionSetupPage> {
  late Map<_PermType, bool> _granted;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _granted = {for (final i in widget.items) i.permission: false};
    _refresh();
  }

  Future<void> _refresh() async {
    final results = <_PermType, bool>{};
    for (final item in widget.items) {
      results[item.permission] = await widget.isGranted(item.permission);
    }
    if (mounted) setState(() => _granted = results);
  }

  Future<void> _tap(_PermType type) async {
    setState(() => _loading = true);
    await widget.onRequest(type);
    await _refresh();
    setState(() => _loading = false);
  }

  bool get _canContinue => true; // Always allow skip/continue

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.phone_in_talk, color: Colors.white, size: 48),
              const SizedBox(height: 24),
              const Text(
                'Set up incoming calls',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Grant the following permissions so you never miss a call or message when the app is closed.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, i) {
                    final item = widget.items[i];
                    final ok = _granted[item.permission] ?? false;
                    return _PermCard(
                      icon: item.icon,
                      title: item.title,
                      description: item.description,
                      granted: ok,
                      onTap: ok ? null : () => _tap(item.permission),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : widget.onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _granted.values.every((v) => v)
                        ? 'Continue'
                        : 'Continue anyway',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback? onTap;

  const _PermCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: granted
            ? const Color(0xFF14532D).withValues(alpha: 0.4)
            : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: granted
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: granted ? Colors.greenAccent : Colors.white70,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        trailing: granted
            ? const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 28,
              )
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Allow', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }
}

enum _PermType { batteryOptimization, displayOverOtherApps }

class _PermItem {
  final _PermType permission;
  final IconData icon;
  final String title;
  final String description;
  const _PermItem({
    required this.permission,
    required this.icon,
    required this.title,
    required this.description,
  });
}
