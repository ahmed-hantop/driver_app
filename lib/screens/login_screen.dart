import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:driver_app/l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/driver_log_service.dart';
import '../locale.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _iqamaController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _iqamaController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiService();

    // Collect device fingerprint for new-device detection on server
    String? deviceId;
    String? deviceModel;
    String? osVersion;
    String? fcmToken;
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceId    = prefs.getString('driver_app_install_device_id');
      deviceModel = Platform.localHostname;
      osVersion   = Platform.operatingSystemVersion;
      fcmToken    = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final success = await api.login(
      _iqamaController.text,
      _passwordController.text,
      deviceId:    deviceId,
      deviceModel: deviceModel,
      osVersion:   osVersion,
      fcmToken:    fcmToken,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      await DriverLogService.instance.flushPending();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      setState(() => _error = l10n.loginFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(width: 16),
                            DropdownButton<String>(
                              value: localeNotifier.value.languageCode,
                              items: [
                                DropdownMenuItem(value: 'en', child: Text(l10n.english)),
                                DropdownMenuItem(value: 'ar', child: Text(l10n.arabic)),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                await saveLocale(value);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            'assets/logo2.png',
                            height: 100,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.business,
                              size: 100,
                              color: Color(0xFF62109F),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _iqamaController,
                          decoration: InputDecoration(
                            labelText: l10n.iqama,
                            prefixIcon: Icon(Icons.person, color: Color(0xFF62109F)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) => value == null || value.isEmpty ? l10n.iqama : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            prefixIcon: Icon(Icons.lock, color: Color(0xFF62109F)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (value) => value == null || value.isEmpty ? l10n.password : null,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/forgot-password');
                            },
                            child: Text(l10n.forgotPassword, style: TextStyle(color: Color(0xFF62109F))),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_error!, style: const TextStyle(color: Colors.red)),
                          ),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF62109F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _loading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(l10n.login, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () async {
                            final url = Uri.parse('https://dobs.speedlogi.sa/register');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Text(l10n.register, style: TextStyle(color: Color(0xFF9C6BB8), fontSize: 14)),
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
