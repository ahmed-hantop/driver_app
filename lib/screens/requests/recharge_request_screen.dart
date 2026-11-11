import 'package:flutter/material.dart';

import '../../models/recharge_request.dart';
import '../../services/request_service.dart';

const _brandPurple = Color(0xFF62109F);
const _operators = ['STC', 'Mobily', 'Zain'];

class RechargeRequestScreen extends StatefulWidget {
  const RechargeRequestScreen({super.key, this.initialMobile});

  final String? initialMobile;

  @override
  State<RechargeRequestScreen> createState() => _RechargeRequestScreenState();
}

class _RechargeRequestScreenState extends State<RechargeRequestScreen> {
  final _service = RequestService();
  late final TextEditingController _mobileCtrl;
  String _operator = _operators.first;

  bool _checkingEligibility = true;
  bool _hasPending = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mobileCtrl = TextEditingController(text: _stripCountryCode(widget.initialMobile));
    _checkEligibility();
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
  }

  String _stripCountryCode(String? mobile) {
    if (mobile == null) return '';
    var value = mobile.trim();
    if (value.startsWith('+966')) value = value.substring(4);
    if (value.startsWith('966')) value = value.substring(3);
    if (value.startsWith('0')) value = value.substring(1);
    return value.trim();
  }

  Future<void> _checkEligibility() async {
    try {
      final result = await _service.fetchRechargeRequests();
      if (!mounted) return;
      setState(() {
        _hasPending = result.pending.isNotEmpty;
        _checkingEligibility = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingEligibility = false);
    }
  }

  void _showHistory() async {
    List<RechargeRequestItem> history = [];
    bool loading = true;
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (loading) {
              _service.fetchRechargeRequests().then((result) {
                setSheetState(() {
                  history = result.history;
                  loading = false;
                });
              }).catchError((e) {
                setSheetState(() {
                  error = e.toString();
                  loading = false;
                });
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (error != null) {
                  return Center(child: Text(error!));
                }
                if (history.isEmpty) {
                  return const Center(child: Text('No recharge requests yet'));
                }
                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final item = history[i];
                    return ListTile(
                      leading: const Icon(Icons.signal_cellular_alt, color: _brandPurple),
                      title: Text('${item.mobile ?? ''} • ${item.operatorName ?? ''}'),
                      subtitle: Text(item.date),
                      trailing: Text(
                        item.status,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    final mobile = _mobileCtrl.text.trim();
    if (mobile.isEmpty) {
      setState(() => _error = 'Enter your mobile number.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await _service.submitRechargeRequest(
      mobile: '+966$mobile',
      operatorName: _operator,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      Navigator.pop(
        context,
        (success: true, message: 'Recharge request sent successfully!'),
      );
      return;
    }

    setState(() => _error = result.message ?? 'Failed to submit recharge request.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internet Recharge'),
        backgroundColor: _brandPurple,
        foregroundColor: Colors.white,
      ),
      body: _checkingEligibility
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _brandPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.signal_cellular_alt, color: _brandPurple, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Request a recharge for your driver mobile number',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: _brandPurple),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _hasPending
                                        ? 'You already have a pending recharge request.'
                                        : 'Only one pending recharge request is allowed.',
                                    style: const TextStyle(color: _brandPurple, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Mobile number',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey.shade50,
                      ),
                      child: const Text('+966'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _mobileCtrl,
                        enabled: !_hasPending,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: '55 123 4567',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Mobile operator',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: _operators.map((op) {
                    final selected = _operator == op;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: op == _operators.last ? 0 : 8),
                        child: InkWell(
                          onTap: _hasPending ? null : () => setState(() => _operator = op),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selected ? _brandPurple : Colors.grey.shade300,
                                width: selected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: selected ? _brandPurple.withValues(alpha: 0.06) : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: selected ? _brandPurple : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(op),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: _showHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Request history'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_submitting || _hasPending) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit recharge request'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'The Operations team will review your request.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
    );
  }
}
