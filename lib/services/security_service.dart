import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class SecurityCheckResult {
  final bool vpnDetected;
  final bool mockLocationDetected;
  final bool gpsAccuracySuspicious;
  final bool rootDetected;
  final bool emulatorDetected;
  final double? gpsAccuracyM;
  final List<String> violations;

  const SecurityCheckResult({
    required this.vpnDetected,
    required this.mockLocationDetected,
    required this.gpsAccuracySuspicious,
    required this.rootDetected,
    required this.emulatorDetected,
    this.gpsAccuracyM,
    this.violations = const [],
  });

  bool get hasHardBlock => vpnDetected || mockLocationDetected || rootDetected;
}

class SecurityService {
  SecurityService._();
  static final SecurityService instance = SecurityService._();

  // VPN interface name prefixes
  static const _vpnPrefixes = ['tun', 'ppp', 'wg', 'ipsec', 'utun', 'tap', 'pptp', 'l2tp', 'vpn'];

  // Real-world GPS accuracy is rarely below 3m — perfect accuracy = likely mock
  static const _suspiciousAccuracyThreshold = 3.0;

  // Known root binaries on Android
  static const _rootPaths = [
    '/system/bin/su',
    '/system/xbin/su',
    '/su/bin/su',
    '/sbin/su',
    '/system/app/SuperSU',
    '/system/app/Magisk',
    '/data/local/tmp/magisk',
  ];

  // Emulator-specific system properties / paths
  static const _emulatorPaths = [
    '/dev/socket/qemud',
    '/dev/qemu_pipe',
    '/system/lib/libc_malloc_debug_qemu.so',
    '/sys/qemu_trace',
    '/system/bin/qemu-props',
  ];

  Future<bool> isVpnActive() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.any,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final prefix in _vpnPrefixes) {
          if (name.startsWith(prefix)) {
            debugPrint('[SecurityService] VPN interface detected: ${iface.name}');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[SecurityService] VPN check failed: $e');
    }
    return false;
  }

  Future<bool> isDeviceRooted() async {
    if (!Platform.isAndroid) return false;
    for (final path in _rootPaths) {
      try {
        if (await File(path).exists()) {
          debugPrint('[SecurityService] Root binary found: $path');
          return true;
        }
      } catch (_) {}
    }
    // Try running `su` — on non-rooted devices this throws or returns non-zero
    try {
      final result = await Process.run('which', ['su']);
      if ((result.stdout as String).trim().isNotEmpty) {
        debugPrint('[SecurityService] `su` found via which');
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> isEmulator() async {
    if (!Platform.isAndroid) return false;
    // Check known emulator paths
    for (final path in _emulatorPaths) {
      try {
        if (await File(path).exists()) {
          debugPrint('[SecurityService] Emulator path found: $path');
          return true;
        }
      } catch (_) {}
    }
    // Check build fingerprint for generic/emulator strings
    try {
      final result = await Process.run('getprop', ['ro.build.fingerprint']);
      final fingerprint = (result.stdout as String).toLowerCase();
      if (fingerprint.contains('generic') || fingerprint.contains('emulator')) {
        debugPrint('[SecurityService] Emulator fingerprint: $fingerprint');
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<SecurityCheckResult> runChecks({Position? position}) async {
    final vpnDetected = await isVpnActive();
    final rootDetected = await isDeviceRooted();
    final emulatorDetected = await isEmulator();

    final mockDetected = position?.isMocked ?? false;
    final accuracy = position?.accuracy;
    final accuracySuspicious = accuracy != null && accuracy < _suspiciousAccuracyThreshold;

    final violations = <String>[
      if (vpnDetected) 'vpn_detected',
      if (mockDetected) 'mock_location',
      if (accuracySuspicious && !mockDetected) 'gps_accuracy_suspicious',
      if (rootDetected) 'root_detected',
      if (emulatorDetected) 'emulator_detected',
    ];

    return SecurityCheckResult(
      vpnDetected: vpnDetected,
      mockLocationDetected: mockDetected || accuracySuspicious,
      gpsAccuracySuspicious: accuracySuspicious,
      rootDetected: rootDetected,
      emulatorDetected: emulatorDetected,
      gpsAccuracyM: accuracy,
      violations: violations,
    );
  }
}
