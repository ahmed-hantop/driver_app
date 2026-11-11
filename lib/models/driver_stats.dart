class DriverStats {
  /// Orders count for the selected filter (defaults to today on backend)
  final int totalOrders;

  /// Delivered orders for the same filter window
  final int deliveredOrders;

  /// Pickup orders for the same filter window
  final int pickupOrders;

  /// Cancelled orders for the same filter window
  final int cancelledOrders;

  /// Delivery success percentage for the selected period
  final double deliveredPercentage;

  /// All orders in the current month
  final int monthlyOrders;

  /// Backwards-compat for the old API shape (was "todayOrdersCount")
  final int todayOrdersCount;

  /// Optional human readable filter summary
  final String? filterLabel;

  DriverStats({
    required this.totalOrders,
    required this.deliveredOrders,
    required this.pickupOrders,
    required this.cancelledOrders,
    required this.deliveredPercentage,
    required this.monthlyOrders,
    required this.todayOrdersCount,
    this.filterLabel,
  });

  factory DriverStats.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '0') ?? 0;
    double asDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

    final filters = json['filters'];
    String? filterLabel;
    if (filters is Map<String, dynamic>) {
      final day = filters['day'];
      final month = filters['month'];
      final year = filters['year'];
      final start = filters['start_date'] ?? filters['start'];
      final end = filters['end_date'] ?? filters['end'];
      if (day != null) {
        filterLabel = 'Day: $day';
      } else if (month != null) {
        filterLabel = 'Month: $month';
      } else if (year != null) {
        filterLabel = 'Year: $year';
      } else if (start != null || end != null) {
        filterLabel = 'Range: ${start ?? '?'} - ${end ?? '?'}';
      }
    }

    final totalOrdersRaw = json['total_orders'] ?? json['totalOrders'] ?? json['today_orders_count'] ?? json['todayOrdersCount'];
    final deliveredOrdersRaw = json['total_delivered_orders'] ?? json['delivered_orders'] ?? json['delivered'] ?? json['completed'];
    final pickupOrdersRaw = json['total_pickup_orders'] ?? json['pickup_orders'] ?? json['pickup'];
    final cancelledOrdersRaw = json['total_cancelled_orders'] ?? json['cancelled_orders'] ?? json['canceled_orders'] ?? json['cancel'];
    final deliveredPercentageRaw = json['percentage_delivered'] ?? json['delivered_percentage'] ?? json['delivery_percentage'];
    final monthlyOrdersRaw = json['monthly_orders'] ?? json['current_month_orders'] ?? json['this_month_orders'];
    final todayOrdersRaw = json['today_orders_count'] ?? json['todayOrdersCount'] ?? json['todayOrders'] ?? totalOrdersRaw;

    return DriverStats(
      totalOrders: asInt(totalOrdersRaw),
      deliveredOrders: asInt(deliveredOrdersRaw),
      pickupOrders: asInt(pickupOrdersRaw),
      cancelledOrders: asInt(cancelledOrdersRaw),
      deliveredPercentage: asDouble(deliveredPercentageRaw),
      monthlyOrders: asInt(monthlyOrdersRaw),
      todayOrdersCount: asInt(todayOrdersRaw),
      filterLabel: filterLabel,
    );
  }
}
