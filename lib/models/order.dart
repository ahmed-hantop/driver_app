class Order {
  final int id;
  final String orderNumber;
  final String businessName;
  final String? businessIdValue;
  final int? businessId;
  final int? businessIdId;
  final String status;
  final DateTime? pickupTime;
  final DateTime? deliveredTime;
  final DateTime? cancelledTime;
  final DateTime? dropTime;
  final DateTime? createdAt;
  final int? type; // 0 wallet, 1 cash, 2 online
  final double? amountReceived;
  final double? amountPaid;

  Order({
    required this.id,
    required this.orderNumber,
    required this.businessName,
    this.businessIdValue,
    this.businessId,
    this.businessIdId,
    this.status = '',
    this.pickupTime,
    this.deliveredTime,
    this.cancelledTime,
    this.dropTime,
    this.createdAt,
    this.type,
    this.amountReceived,
    this.amountPaid,
  });

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  static double? _parseDouble(dynamic raw) {
    if (raw == null) return null;
    final parsed = double.tryParse(raw.toString());
    return parsed;
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    final idValue = json['id'];
    final business = json['business'] is Map ? json['business'] as Map : null;
    final businessId = json['business_id'];
    final businessIdId = json['business_id_id'] ?? json['business_ids_id'];
    final orderNumber = json['order_id'] ?? json['order_number'] ?? json['value'] ?? json['order'];

    return Order(
      id: (idValue is num) ? idValue.toInt() : int.tryParse(idValue?.toString() ?? '0') ?? 0,
      orderNumber: orderNumber?.toString() ?? '',
      businessName: (json['business_name'] ?? business?['name'] ?? json['business'] ?? 'Order').toString(),
      businessIdValue: (json['business_id_value'] ?? json['business_id'] ?? '').toString().isNotEmpty
          ? (json['business_id_value'] ?? json['business_id'] ?? '').toString()
          : (json['businessId'] is Map ? (json['businessId']['value']?.toString() ?? '') : ''),
      businessId: (businessId is num) ? businessId.toInt() : int.tryParse(businessId?.toString() ?? ''),
      businessIdId: (businessIdId is num) ? businessIdId.toInt() : int.tryParse(businessIdId?.toString() ?? ''),
      status: (json['status'] ?? '').toString(),
      pickupTime: _parseDate(json['pickup_time'] ?? json['pickupTime']),
      deliveredTime: _parseDate(json['delivered_time'] ?? json['deliveredTime'] ?? json['delivered_at'] ?? json['drop_time']),
      cancelledTime: _parseDate(json['cancelled_time'] ?? json['cancelledTime']),
      dropTime: _parseDate(json['drop_time']),
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      type: json['type'] is num ? (json['type'] as num).toInt() : int.tryParse(json['type']?.toString() ?? ''),
      amountReceived: _parseDouble(json['amount_received']),
      amountPaid: _parseDouble(json['amount_paid']),
    );
  }

  bool get isPickedUp => status.toLowerCase() == 'pickup';
  bool get isDelivered {
    final s = status.toLowerCase();
    return deliveredTime != null || s == 'drop' || s == 'delivered' || s.contains('deliver');
  }
  bool get isCancelled {
    final s = status.toLowerCase();
    return cancelledTime != null || s == 'cancel' || s == 'cancelled' || s.contains('cancel');
  }
}
