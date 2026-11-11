import 'package:flutter/material.dart';
import '../../models/payroll_slip.dart';
import '../../services/payroll_service.dart';

class PayrollDetailScreen extends StatefulWidget {
  final int slipId;
  const PayrollDetailScreen({super.key, required this.slipId});

  @override
  State<PayrollDetailScreen> createState() => _PayrollDetailScreenState();
}

class _PayrollDetailScreenState extends State<PayrollDetailScreen> {
  final _service = PayrollService();
  PayrollSlipDetail? _slip;
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
      final slip = await _service.fetchSlipDetail(widget.slipId);
      if (mounted)
        setState(() {
          _slip = slip;
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _slip != null
              ? '${_slip!.monthName} ${_slip!.year} Payslip'
              : 'Payslip',
        ),
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final s = _slip!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header card
        _SectionCard(
          color: const Color(0xFF6A1B9A),
          child: Column(
            children: [
              Text(
                '${s.monthName} ${s.year}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'SAR ${s.netSalary.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: s.isPaid
                      ? Colors.green
                      : (s.isSettled
                            ? Colors.orange
                            : Colors.white.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      s.isPaid
                          ? Icons.check_circle
                          : (s.isSettled
                                ? Icons.calendar_month
                                : Icons.schedule),
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.isPaid
                          ? 'PAID'
                          : (s.isSettled
                                ? s.settledInLabel.toUpperCase()
                                : s.status.toUpperCase()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.isPaid && s.salaryPaidThisMonth > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Amount Paid: SAR ${s.salaryPaidThisMonth.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (s.isSettled) ...[
                const SizedBox(height: 8),
                Text(
                  'Carry forward to next month',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
              if (!s.isAcknowledged) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF6A1B9A),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Acknowledge Receipt'),
                  onPressed: () async {
                    await _service.acknowledge(s.id);
                    _load();
                  },
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Orders summary
        _detailSection('Orders Summary', [
          _row('HungerStation', '${s.hungerStationOrders}'),
          _row('Jahez', '${s.jahezOrders}'),
          _row('Other Platforms', '${s.otherPlatformOrders}'),
          _divider(),
          _row('Total Orders', '${s.totalOrders}', bold: true),
          _row('Target', '${s.targetToAchieve}'),
        ]),

        const SizedBox(height: 12),

        // Earnings
        _detailSection('Earnings', [
          _row('Base Salary', 'SAR ${s.baseSalary.toStringAsFixed(2)}'),
          if (s.tier1Addition > 0)
            _row(
              'Tier 1 Bonus',
              '+ SAR ${s.tier1Addition.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          if (s.tier2Addition > 0)
            _row(
              'Tier 2 Bonus',
              '+ SAR ${s.tier2Addition.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          if (s.tier3Addition > 0)
            _row(
              'Tier 3 Bonus',
              '+ SAR ${s.tier3Addition.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          if (s.bonus1Addition > 0)
            _row(
              'Bonus 1',
              '+ SAR ${s.bonus1Addition.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          if (s.bonus2Addition > 0)
            _row(
              'Bonus 2',
              '+ SAR ${s.bonus2Addition.toStringAsFixed(2)}',
              color: Colors.green,
            ),
          _divider(),
          _row(
            'Gross Earnings',
            'SAR ${s.grossEarnings.toStringAsFixed(2)}',
            bold: true,
          ),
        ]),

        const SizedBox(height: 12),

        // Deductions
        _detailSection('Deductions', [
          if (s.hungerStationPenalty > 0)
            _row(
              'HungerStation Penalty',
              '− SAR ${s.hungerStationPenalty.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.jahezPenalty > 0)
            _row(
              'Jahez Penalty',
              '− SAR ${s.jahezPenalty.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.otherPenalty > 0)
            _row(
              'Other Penalty',
              '− SAR ${s.otherPenalty.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.cashShortage > 0)
            _row(
              'Cash Shortage',
              '− SAR ${s.cashShortage.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.fuelDeduction > 0)
            _row(
              'Fuel Deduction',
              '− SAR ${s.fuelDeduction.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.walletDeduction > 0)
            _row(
              'Wallet Deduction',
              '− SAR ${s.walletDeduction.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.advanceSalary > 0)
            _row(
              'Advance Salary',
              '− SAR ${s.advanceSalary.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.sponsorshipDeduction > 0)
            _row(
              'Sponsorship',
              '− SAR ${s.sponsorshipDeduction.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          if (s.accidentDeductionItems.isNotEmpty)
            for (final item in s.accidentDeductionItems)
              _row(
                'Accident #${item.accidentNumber}',
                '− SAR ${item.amount.toStringAsFixed(2)}',
                color: Colors.red,
              )
          else if (s.accidentDeduction > 0)
            _row(
              'Accident Deduction',
              '− SAR ${s.accidentDeduction.toStringAsFixed(2)}',
              color: Colors.red,
            ),
          _divider(),
          _row(
            'Total Deductions',
            '− SAR ${s.totalDeductions.toStringAsFixed(2)}',
            bold: true,
            color: Colors.red,
          ),
        ]),

        const SizedBox(height: 12),

        // Final
        _detailSection('Final Calculation', [
          _row('Gross Earnings', 'SAR ${s.grossEarnings.toStringAsFixed(2)}'),
          _row(
            'Total Deductions',
            '− SAR ${s.totalDeductions.toStringAsFixed(2)}',
            color: Colors.red,
          ),
          _divider(),
          _row(
            'Net Salary',
            'SAR ${s.netSalary.toStringAsFixed(2)}',
            bold: true,
          ),
          if (s.previousMonthBalance != 0)
            _row(
              'Previous Balance',
              '${s.previousMonthBalance >= 0 ? '+' : ''} SAR ${s.previousMonthBalance.toStringAsFixed(2)}',
              color: s.previousMonthBalance < 0 ? Colors.red : Colors.green,
            ),
          _divider(),
          _row(
            'Total Payable',
            'SAR ${s.totalPayable.toStringAsFixed(2)}',
            bold: true,
            large: true,
          ),
          _row(
            'Paid This Month',
            'SAR ${s.salaryPaidThisMonth.toStringAsFixed(2)}',
            color: Colors.green,
          ),
          _row(
            'Closing Balance',
            'SAR ${s.closingBalance.toStringAsFixed(2)}',
            bold: true,
            color: s.closingBalance < 0 ? Colors.red : Colors.black87,
          ),
        ]),

        if (s.paymentBankName != null || s.paymentIban != null) ...[
          const SizedBox(height: 12),
          _detailSection('Payment Details', [
            if (s.paymentBankName != null) _row('Bank', s.paymentBankName!),
            if (s.paymentAccountName != null)
              _row('Account Name', s.paymentAccountName!),
            if (s.paymentIban != null) _row('IBAN', s.paymentIban!),
          ]),
        ],

        if (s.additionalComments != null &&
            s.additionalComments!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _detailSection('Comments', [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                s.additionalComments!,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
          ]),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF6A1B9A),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    bool large = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: large ? 15 : 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: large ? 15 : 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Divider(height: 1),
  );
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color color;
  const _SectionCard({required this.child, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
