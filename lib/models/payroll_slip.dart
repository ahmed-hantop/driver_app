class AccidentDeductionItem {
  final String accidentNumber;
  final double amount;

  AccidentDeductionItem({required this.accidentNumber, required this.amount});

  factory AccidentDeductionItem.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null
        ? 0.0
        : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
    return AccidentDeductionItem(
      accidentNumber: (j['accident_number'] ?? 'N/A').toString(),
      amount: d(j['amount']),
    );
  }
}

class PayrollSlip {
  final int id;
  final int month;
  final int year;
  final String status;
  final String payrollType;
  final double netSalary;
  final int totalOrders;
  final double totalPayable;
  final double salaryPaidThisMonth;
  final double closingBalance;
  final String? paymentBankName;
  final String? driverAcknowledgedAt;
  final int? settlementMonth;
  final int? settlementYear;

  PayrollSlip({
    required this.id,
    required this.month,
    required this.year,
    required this.status,
    required this.payrollType,
    required this.netSalary,
    required this.totalOrders,
    required this.totalPayable,
    required this.salaryPaidThisMonth,
    required this.closingBalance,
    this.paymentBankName,
    this.driverAcknowledgedAt,
    this.settlementMonth,
    this.settlementYear,
  });

  factory PayrollSlip.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null
        ? 0.0
        : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
    int i(dynamic v) =>
        v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);
    return PayrollSlip(
      id: i(j['id']),
      month: i(j['month']),
      year: i(j['year']),
      status: (j['status'] ?? '').toString(),
      payrollType: (j['payroll_type'] ?? 'manual').toString(),
      netSalary: d(j['net_salary']),
      totalOrders: i(j['total_orders']),
      totalPayable: d(j['total_payable']),
      salaryPaidThisMonth: d(j['salary_paid_this_month']),
      closingBalance: d(j['closing_balance']),
      paymentBankName: j['payment_bank_name']?.toString(),
      driverAcknowledgedAt: j['driver_acknowledged_at']?.toString(),
      settlementMonth: j['settlement_month'] == null
          ? null
          : int.tryParse(j['settlement_month'].toString()),
      settlementYear: j['settlement_year'] == null
          ? null
          : int.tryParse(j['settlement_year'].toString()),
    );
  }

  String get monthName {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return month >= 1 && month <= 12 ? months[month] : '$month';
  }

  bool get isPaid => status.toLowerCase() == 'paid';
  bool get isSettled => status.toLowerCase() == 'settled';
  bool get hasPaymentDetails =>
      paymentBankName != null && paymentBankName!.isNotEmpty;
  bool get isAcknowledged =>
      driverAcknowledgedAt != null && driverAcknowledgedAt!.isNotEmpty;

  static const _monthNames = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get settledInLabel {
    if (settlementMonth != null &&
        settlementYear != null &&
        settlementMonth! >= 1 &&
        settlementMonth! <= 12) {
      return 'Settled in ${_monthNames[settlementMonth!]} $settlementYear';
    }
    return 'Settled';
  }
}

class PayrollSlipDetail extends PayrollSlip {
  // Orders
  final int hungerStationOrders;
  final int jahezOrders;
  final int otherPlatformOrders;
  final int targetToAchieve;
  // Earnings
  final double baseSalary;
  final double tier1Addition;
  final double tier2Addition;
  final double tier3Addition;
  final double bonus1Addition;
  final double bonus2Addition;
  final double totalSalary;
  // Penalties
  final double hungerStationPenalty;
  final double jahezPenalty;
  final double otherPenalty;
  final double totalPenalties;
  // Deductions
  final double cashShortage;
  final double fuelDeduction;
  final double walletDeduction;
  final double advanceSalary;
  final double sponsorshipDeduction;
  final double accidentDeduction;
  final List<AccidentDeductionItem> accidentDeductionItems;
  final double totalDeductions;
  // Final
  final double previousMonthBalance;
  // Payment
  final String? paymentType;
  @override
  final String? paymentBankName;
  final String? paymentIban;
  final String? paymentAccountName;
  final String? additionalComments;
  // Signatories
  final String? preparedBy;
  final String? checkedBy;
  final String? approvedBy;

  PayrollSlipDetail({
    required super.id,
    required super.month,
    required super.year,
    required super.status,
    required super.payrollType,
    required super.netSalary,
    required super.totalOrders,
    required super.totalPayable,
    required super.salaryPaidThisMonth,
    required super.closingBalance,
    super.driverAcknowledgedAt,
    super.settlementMonth,
    super.settlementYear,
    required this.hungerStationOrders,
    required this.jahezOrders,
    required this.otherPlatformOrders,
    required this.targetToAchieve,
    required this.baseSalary,
    required this.tier1Addition,
    required this.tier2Addition,
    required this.tier3Addition,
    required this.bonus1Addition,
    required this.bonus2Addition,
    required this.totalSalary,
    required this.hungerStationPenalty,
    required this.jahezPenalty,
    required this.otherPenalty,
    required this.totalPenalties,
    required this.cashShortage,
    required this.fuelDeduction,
    required this.walletDeduction,
    required this.advanceSalary,
    required this.sponsorshipDeduction,
    required this.accidentDeduction,
    this.accidentDeductionItems = const [],
    required this.totalDeductions,
    required this.previousMonthBalance,
    this.paymentType,
    this.paymentBankName,
    this.paymentIban,
    this.paymentAccountName,
    this.additionalComments,
    this.preparedBy,
    this.checkedBy,
    this.approvedBy,
  });

  factory PayrollSlipDetail.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null
        ? 0.0
        : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
    int i(dynamic v) =>
        v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);
    return PayrollSlipDetail(
      id: i(j['id']),
      month: i(j['month']),
      year: i(j['year']),
      status: (j['status'] ?? '').toString(),
      payrollType: (j['payroll_type'] ?? 'manual').toString(),
      netSalary: d(j['net_salary']),
      totalOrders: i(j['total_orders']),
      totalPayable: d(j['total_payable']),
      salaryPaidThisMonth: d(j['salary_paid_this_month']),
      closingBalance: d(j['closing_balance']),
      driverAcknowledgedAt: j['driver_acknowledged_at']?.toString(),
      settlementMonth: j['settlement_month'] == null
          ? null
          : int.tryParse(j['settlement_month'].toString()),
      settlementYear: j['settlement_year'] == null
          ? null
          : int.tryParse(j['settlement_year'].toString()),
      hungerStationOrders: i(j['hunger_station_orders']),
      jahezOrders: i(j['jahez_orders']),
      otherPlatformOrders: i(j['other_platform_orders']),
      targetToAchieve: i(j['target_to_achieve']),
      baseSalary: d(j['base_salary']),
      tier1Addition: d(j['tier1_addition']),
      tier2Addition: d(j['tier2_addition']),
      tier3Addition: d(j['tier3_addition']),
      bonus1Addition: d(j['bonus1_addition']),
      bonus2Addition: d(j['bonus2_addition']),
      totalSalary: d(j['total_salary']),
      hungerStationPenalty: d(j['hunger_station_penalty']),
      jahezPenalty: d(j['jahez_penalty']),
      otherPenalty: d(j['other_penalty']),
      totalPenalties: d(j['total_penalties']),
      cashShortage: d(j['cash_shortage']),
      fuelDeduction: d(j['fuel_deduction']),
      walletDeduction: d(j['wallet_deduction']),
      advanceSalary: d(j['advance_salary']),
      sponsorshipDeduction: d(j['sponsorship_deduction']),
      accidentDeduction: d(j['accident_deduction']),
      accidentDeductionItems: (j['accident_deduction_items'] as List<dynamic>?)
              ?.map(
                (item) => AccidentDeductionItem.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList() ??
          const [],
      totalDeductions: d(j['total_deductions']),
      previousMonthBalance: d(j['previous_month_balance']),
      paymentType: j['payment_type']?.toString(),
      paymentBankName: j['payment_bank_name']?.toString(),
      paymentIban: j['payment_iban']?.toString(),
      paymentAccountName: j['payment_account_name']?.toString(),
      additionalComments: j['additional_comments']?.toString(),
      preparedBy: j['prepared_by_user']?['name']?.toString(),
      checkedBy: j['checked_by_user']?['name']?.toString(),
      approvedBy: j['approved_by_user']?['name']?.toString(),
    );
  }

  double get grossEarnings =>
      baseSalary +
      tier1Addition +
      tier2Addition +
      tier3Addition +
      bonus1Addition +
      bonus2Addition;
}
