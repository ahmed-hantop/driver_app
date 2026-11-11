import 'package:flutter/material.dart';
import '../../models/payroll_slip.dart';
import '../../services/payroll_service.dart';
import 'payroll_detail_screen.dart';

class PayrollListScreen extends StatefulWidget {
  const PayrollListScreen({super.key});

  @override
  State<PayrollListScreen> createState() => _PayrollListScreenState();
}

class _PayrollListScreenState extends State<PayrollListScreen> {
  final _service = PayrollService();
  List<PayrollSlip> _slips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slips = await _service.fetchSlips();
      if (mounted)
        setState(() {
          _slips = slips;
          _loading = false;
        });
    } on PayrollFeatureDisabledException {
      if (mounted)
        setState(() {
          _error = 'disabled';
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error == 'disabled') {
      return _emptyState(
        icon: Icons.lock_outline,
        title: 'Payroll Unavailable',
        subtitle:
            'The payroll feature is currently disabled. Contact your manager for more information.',
        color: Colors.orange,
      );
    }
    if (_error != null) {
      return _emptyState(
        icon: Icons.error_outline,
        title: 'Failed to load',
        subtitle: _error!,
        color: Colors.red,
        action: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_slips.isEmpty) {
      return _emptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No salary slips yet',
        subtitle: 'Your approved payroll slips will appear here.',
        color: const Color(0xFF6A1B9A),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _slips.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _SlipCard(slip: _slips[i]),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            if (action != null) ...[const SizedBox(height: 12), action],
          ],
        ),
      ),
    );
  }
}

class _SlipCard extends StatelessWidget {
  final PayrollSlip slip;
  const _SlipCard({required this.slip});

  @override
  Widget build(BuildContext context) {
    final isPaid = slip.isPaid;
    final isSettled = slip.isSettled;
    final hasPayment = slip.hasPaymentDetails;

    String badgeLabel;
    Color badgeColor;
    if (isPaid) {
      badgeLabel = 'Paid';
      badgeColor = Colors.green;
    } else if (isSettled) {
      badgeLabel = slip.settledInLabel;
      badgeColor = Colors.orange;
    } else if (hasPayment) {
      badgeLabel = 'Payment Added';
      badgeColor = Colors.blue;
    } else {
      badgeLabel = 'Pending';
      badgeColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PayrollDetailScreen(slipId: slip.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long, color: Color(0xFF6A1B9A)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slip.monthName} ${slip.year}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _badge(badgeLabel, badgeColor),
                        if (!slip.isAcknowledged) ...[
                          const SizedBox(width: 6),
                          _badge('New', const Color(0xFF6A1B9A)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'SAR ${slip.netSalary.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF6A1B9A),
                    ),
                  ),
                  Text(
                    '${slip.totalOrders} orders',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
