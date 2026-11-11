class BusinessIdItem {
  final int? id; // backend business_ids primary key
  final String value;

  BusinessIdItem({this.id, required this.value});

  factory BusinessIdItem.fromJson(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      final idVal = raw['id'] ?? raw['business_id_id'] ?? raw['business_ids_id'];
      return BusinessIdItem(
        id: (idVal is num) ? idVal.toInt() : int.tryParse(idVal?.toString() ?? ''),
        value: (raw['value'] ?? raw['business_id_value'] ?? raw['platform_id'] ?? '').toString(),
      );
    }
    return BusinessIdItem(id: null, value: raw?.toString() ?? '');
  }
}

class Business {
  final int? id;
  final String name;
  final String? image;
  final List<String> ids; // legacy string-only list for display compatibility
  final List<BusinessIdItem> businessIds; // structured business_id rows
  final String? platformId;

  Business({
    this.id,
    required this.name,
    this.image,
    this.ids = const [],
    this.businessIds = const [],
    this.platformId,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    final idValue = json['id'];
    final idsRaw = json['ids'] ?? json['business_ids'] ?? json['assigned_ids'] ?? [];
    final platformId = json['platform_id'] ?? json['platformId'] ?? json['platformID'];

    List<String> parsedIds = [];
    List<BusinessIdItem> parsedBusinessIds = [];
    if (idsRaw is List) {
      parsedIds = idsRaw.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
      parsedBusinessIds = idsRaw
          .map((e) => BusinessIdItem.fromJson(e))
          .where((e) => e.value.isNotEmpty)
          .toList();
    }

    return Business(
      id: (idValue is num) ? idValue.toInt() : int.tryParse(idValue?.toString() ?? ''),
      name: (json['name'] ?? json['business_name'] ?? 'Business').toString(),
      image: json['image']?.toString(),
      ids: parsedIds,
      businessIds: parsedBusinessIds,
      platformId: platformId?.toString(),
    );
  }
}
