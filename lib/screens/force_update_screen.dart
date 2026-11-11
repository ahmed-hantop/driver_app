import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:driver_app/l10n/app_localizations.dart';
import 'package:driver_app/services/app_update_service.dart';

class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({
    super.key,
    required this.message,
    required this.updateUrl,
    required this.currentVersion,
    required this.latestVersion,
  });

  final String message;
  final String updateUrl;
  final String currentVersion;
  final String latestVersion;

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  bool _openingStore = false;

  Future<void> _openUpdateUrl() async {
    if (_openingStore) return;
    final l10n = AppLocalizations.of(context)!;
    if (widget.updateUrl.isEmpty) {
      _showSnackBar(l10n.forceUpdateLinkMissing);
      return;
    }

    setState(() {
      _openingStore = true;
    });

    try {
      final uri = AppUpdateService.instance.allowedUpdateUri(widget.updateUrl);
      if (uri == null) {
        _showSnackBar(l10n.forceUpdateLinkInvalidConfig);
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        _showSnackBar(l10n.forceUpdateLinkOpenFailed);
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar(l10n.forceUpdateLinkInvalid);
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingStore = false;
        });
      }
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.system_update_alt, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          l10n.forceUpdateTitle,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.message,
                          style: const TextStyle(fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.forceUpdateVersionSummary(widget.currentVersion, widget.latestVersion),
                          style: TextStyle(color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openingStore ? null : _openUpdateUrl,
                            icon: _openingStore
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.open_in_new),
                            label: Text(_openingStore ? l10n.forceUpdateOpening : l10n.forceUpdateNow),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.forceUpdateBlockedMessage,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
