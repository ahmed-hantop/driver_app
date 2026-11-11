import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:driver_app/l10n/app_localizations.dart';
import 'package:driver_app/l10n/app_localization_helper.dart';
import 'package:driver_app/screens/force_update_screen.dart';
import 'package:driver_app/services/app_update_service.dart';
import 'package:driver_app/services/api_service.dart';
import '../services/ota_update_service.dart';
import '../services/call_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  String _statusText = currentAppLocalizations().splashCheckingUpdates;
  String _appVersion = '';

  AppLocalizations get _l10n => currentAppLocalizations();

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() {
      _statusText = value;
    });
  }

  void _showRestartingDialog() {
    if (!mounted) return;
    final l10n = _l10n;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.splashUpdateReadyTitle),
          content: Text(l10n.splashUpdateReadyBody),
        );
      },
    );
  }

  Future<bool> _waitForAcceptedCallToEnd() async {
    while (mounted && CallState.callScreenActive) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return mounted;
  }

  Future<void> _startSplashFlow() async {
    final minSplashTime = Future<void>.delayed(const Duration(seconds: 2));
    final l10n = _l10n;
    _setStatus(l10n.splashCheckingUpdates);
    final otaResult = await OtaUpdateService.instance.checkAndDownloadUpdate();

    _setStatus(l10n.splashCheckingVersion);
    final appUpdate = await AppUpdateService.instance.checkForRequiredUpdate();
    await minSplashTime;

    if (!mounted) return;

    // A CallKit accept can cold-start Flutter while this splash flow is still
    // checking updates. Wait for the call route rather than returning; a bare
    // return leaves this splash screen frozen after the call ends.
    if (!await _waitForAcceptedCallToEnd()) return;

    if (appUpdate.mustUpdate) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ForceUpdateScreen(
            message: appUpdate.message,
            updateUrl: appUpdate.updateUrl,
            currentVersion: appUpdate.currentVersion,
            latestVersion: appUpdate.latestVersion,
          ),
        ),
      );
      return;
    }

    if (otaResult == OtaCheckResult.restartRequired) {
      // Shorebird applies downloaded patches on next app start.
      // Close app after notifying the user so reopening loads the patch.
      _setStatus(l10n.splashUpdateDownloadedRestarting);
      _showRestartingDialog();
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      SystemNavigator.pop();
      return;
    }

    if (otaResult == OtaCheckResult.failed) {
      _setStatus(l10n.splashUpdateCheckFailedOpening);
    } else if (otaResult == OtaCheckResult.unavailable) {
      _setStatus(l10n.splashUpdatesUnavailableOpening);
    } else {
      _setStatus(l10n.splashOpeningApp);
    }

    _setStatus(l10n.splashValidatingSession);
    final hasValidSession = await _apiService.hasValidStoredSession();

    if (!mounted) return;

    if (!await _waitForAcceptedCallToEnd()) return;

    final nextRoute = hasValidSession ? '/dashboard' : '/login';
    Navigator.pushReplacementNamed(context, nextRoute);
  }

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();
    _startSplashFlow();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Opacity(
                      opacity: _opacityAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/logo2.png',
                          width: 150,
                          height: 150,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.business,
                            size: 150,
                            color: Color(0xFF62109F),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              if (_appVersion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _appVersion,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
