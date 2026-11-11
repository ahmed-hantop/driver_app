class RechargeRequestItem {
  final int id;
  final String status;
  final String? mobile;
  final String? operatorName;
  final String? reason;
  final String date;
  final String? dateOnly;
  final String? approvedBy;
  final String? approvedDate;
  final double? rechargedAmount;
  final String? rechargedDate;
  final String? rechargedBy;
  final String? rechargeProofUrl;

  RechargeRequestItem({
    required this.id,
    required this.status,
    this.mobile,
    this.operatorName,
    this.reason,
    required this.date,
    this.dateOnly,
    this.approvedBy,
    this.approvedDate,
    this.rechargedAmount,
    this.rechargedDate,
    this.rechargedBy,
    this.rechargeProofUrl,
  });

  factory RechargeRequestItem.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return RechargeRequestItem(
      id: toInt(json['id']),
      status: (json['status'] ?? '').toString(),
      mobile: json['mobile']?.toString(),
      operatorName: (json['operator'] ?? json['opearator'])?.toString(),
      reason: json['reason']?.toString(),
      date: (json['date'] ?? '').toString(),
      dateOnly: json['date_only']?.toString(),
      approvedBy: json['approved_by']?.toString(),
      approvedDate: json['approved_date']?.toString(),
      rechargedAmount: toDouble(json['recharged_amount']),
      rechargedDate: json['recharged_date']?.toString(),
      rechargedBy: json['recharged_by']?.toString(),
      rechargeProofUrl: json['recharge_proof_url']?.toString(),
    );
  }

  bool get isPending => status.toLowerCase() == 'pending';
}
