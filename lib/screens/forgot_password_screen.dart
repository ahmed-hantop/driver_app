import 'package:flutter/material.dart';
import 'package:driver_app/services/api_service.dart';
import 'package:driver_app/l10n/app_localizations.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailOrIqamaController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _otpSent = false;
  bool _otpVerified = false;
  bool _sending = false;
  bool _verifying = false;
  bool _resetting = false;
  String? _statusMessage;
  bool _statusIsSuccess = false;

  @override
  void dispose() {
    _emailOrIqamaController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final l10n = AppLocalizations.of(context)!;
    if (_emailOrIqamaController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = l10n.forgotEnterIqamaOrEmail;
        _statusIsSuccess = false;
      });
      return;
    }
    setState(() {
      _sending = true;
      _statusMessage = null;
      _statusIsSuccess = false;
    });
    final api = ApiService();
    final result = await api.requestPasswordReset(
      emailOrIqama: _emailOrIqamaController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _otpSent = result.success;
      _otpVerified = false;
      _statusMessage = result.message ??
          (result.success ? l10n.forgotOtpSent : l10n.forgotOtpSendFailed);
      _statusIsSuccess = result.success;
    });
  }

  Future<void> _verifyOtp() async {
    final l10n = AppLocalizations.of(context)!;
    if (_otpController.text.trim().length != 6) {
      setState(() {
        _statusMessage = l10n.forgotEnterOtp;
        _statusIsSuccess = false;
      });
      return;
    }
    setState(() {
      _verifying = true;
      _statusMessage = null;
      _statusIsSuccess = false;
    });
    final api = ApiService();
    final result = await api.verifyResetOtp(
      emailOrIqama: _emailOrIqamaController.text.trim(),
      otp: _otpController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _otpVerified = result.success;
      _statusMessage = result.message ??
          (result.success ? l10n.forgotOtpVerified : l10n.forgotOtpVerificationFailed);
      _statusIsSuccess = result.success;
    });
  }

  Future<void> _resendOtp() async {
    final l10n = AppLocalizations.of(context)!;
    if (_emailOrIqamaController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = l10n.forgotEnterIqamaOrEmailFirst;
        _statusIsSuccess = false;
      });
      return;
    }
    setState(() {
      _sending = true;
      _statusMessage = null;
      _statusIsSuccess = false;
    });
    final api = ApiService();
    final result = await api.resendResetOtp(
      emailOrIqama: _emailOrIqamaController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _otpSent = result.success || _otpSent;
      _otpVerified = false;
      _statusMessage = result.message ??
          (result.success ? l10n.forgotOtpResent : l10n.forgotOtpResendFailed);
      _statusIsSuccess = result.success;
    });
  }

  Future<void> _resetPassword() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_otpVerified) {
      setState(() {
        _statusMessage = l10n.forgotVerifyOtpFirst;
        _statusIsSuccess = false;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _resetting = true;
      _statusMessage = null;
    });
    final api = ApiService();
    final result = await api.confirmResetPassword(
      emailOrIqama: _emailOrIqamaController.text.trim(),
      otp: _otpController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _confirmPasswordController.text,
    );

    if (!mounted) return;
    setState(() {
      _resetting = false;
      _statusMessage = result.message ??
          (result.success ? l10n.forgotPasswordResetSuccessMessage : l10n.forgotPasswordResetFailed);
      _statusIsSuccess = result.success;
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.forgotPasswordResetSnackBar)),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.forgotPassword),
        backgroundColor: const Color(0xFF62109F),
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.forgotRecoverTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.forgotRecoverSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _emailOrIqamaController,
                        decoration: InputDecoration(
                          labelText: l10n.forgotIqamaOrEmailLabel,
                          prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF62109F)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        keyboardType: TextInputType.text,
                        validator: (value) =>
                            value == null || value.isEmpty ? l10n.forgotIqamaOrEmailValidation : null,
                      ),
                      const SizedBox(height: 12),
                      if (!_otpSent) ...[
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _sending ? null : _sendOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF62109F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(l10n.forgotSendOtp),
                          ),
                        ),
                      ],
                      if (_otpSent) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.forgotOtpSentPrompt,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _otpController,
                          decoration: InputDecoration(
                            labelText: l10n.forgotOtpLabel,
                            prefixIcon: const Icon(Icons.key, color: Color(0xFF62109F)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _verifying ? null : _verifyOtp,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF62109F)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _verifying
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(l10n.forgotVerifyOtp),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: _sending ? null : _resendOtp,
                                child: Text(l10n.forgotResend),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_otpVerified) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF62109F)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (value) =>
                              value != null && value.length >= 8 ? null : l10n.forgotPasswordMinLength,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: InputDecoration(
                            labelText: l10n.forgotConfirmPassword,
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFF62109F)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                          ),
                          obscureText: _obscureConfirmPassword,
                          validator: (value) => value == _passwordController.text
                              ? null
                              : l10n.forgotPasswordsMismatch,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _resetting ? null : _resetPassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF62109F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _resetting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(l10n.forgotResetPassword),
                          ),
                        ),
                      ],
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _statusIsSuccess ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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
