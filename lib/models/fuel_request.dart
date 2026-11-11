class FuelAssignedVehicle {
  final int? id;
  final String? name;
  final String? plateNumber;
  final String? fuelType;

  FuelAssignedVehicle({this.id, this.name, this.plateNumber, this.fuelType});

  factory FuelAssignedVehicle.fromJson(Map<String, dynamic> json) {
    return FuelAssignedVehicle(
      id: json['id'] is num ? (json['id'] as num).toInt() : int.tryParse(json['id']?.toString() ?? ''),
      name: json['name']?.toString(),
      plateNumber: json['plate_number']?.toString(),
      fuelType: json['fuel_type']?.toString(),
    );
  }
}

class FuelRequestItem {
  final int id;
  final String? fuelType;
  final double? amount;
  final String status;
  final String date;
  final String? dateOnly;
  final int? orders;
  final String? rejectNotes;
  final String? rejectBy;
  final String? rejectDate;
  final double? approvedAmount;
  final String? approvedBy;
  final String? approvalDate;
  final String? notes;
  final double? estimatedCost;
  final String? scheduledDate;

  FuelRequestItem({
    required this.id,
    this.fuelType,
    this.amount,
    required this.status,
    required this.date,
    this.dateOnly,
    this.orders,
    this.rejectNotes,
    this.rejectBy,
    this.rejectDate,
    this.approvedAmount,
    this.approvedBy,
    this.approvalDate,
    this.notes,
    this.estimatedCost,
    this.scheduledDate,
  });

  factory FuelRequestItem.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return FuelRequestItem(
      id: toInt(json['id']) ?? 0,
      fuelType: json['type']?.toString(),
      amount: toDouble(json['amount']),
      status: (json['status'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      dateOnly: json['date_only']?.toString(),
      orders: toInt(json['orders']),
      rejectNotes: json['reject_notes']?.toString(),
      rejectBy: json['reject_by']?.toString(),
      rejectDate: json['reject_date']?.toString(),
      approvedAmount: toDouble(json['approved_amount']),
      approvedBy: json['approved_by']?.toString(),
      approvalDate: json['approval_date']?.toString(),
      notes: json['notes']?.toString(),
      estimatedCost: toDouble(json['estimated_cost']),
      scheduledDate: json['scheduled_date']?.toString(),
    );
  }

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
}
