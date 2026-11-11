class DriverProfile {
  final int id;
  final String name;
  final String? image;
  final String status;
  final String? mobile;
  final String? nationality;
  final String? language;
  final String? branchName;
  final int totalOrders;
  final double? lat;
  final double? lng;
  final String? locationAddress;
  final String? mapboxToken;
  final String? mapboxStyle;
  final double? mapboxCenterLat;
  final double? mapboxCenterLng;
  final double? mapboxZoom;
  final String? updatedAt;
  final bool payrollEnabled;
  final bool chatEnabled;
  final bool callsEnabled;

  DriverProfile({
    required this.id,
    required this.name,
    this.image,
    required this.status,
    this.mobile,
    this.nationality,
    this.language,
    this.branchName,
    this.totalOrders = 0,
    this.lat,
    this.lng,
    this.locationAddress,
    this.mapboxToken,
    this.mapboxStyle,
    this.mapboxCenterLat,
    this.mapboxCenterLng,
    this.mapboxZoom,
    this.updatedAt,
    this.payrollEnabled = true,
    this.chatEnabled    = true,
    this.callsEnabled   = true,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> raw) {
    final json = raw['driver'] is Map<String, dynamic> ? raw['driver'] as Map<String, dynamic> : raw;
    final idValue = json['id'];
    final mapbox = json['mapbox'] as Map<String, dynamic>?;
    double? toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '');
    }
    double? centerLat;
    double? centerLng;
    if (mapbox != null) {
      final center = mapbox['center'];
      if (center is Map) {
        centerLat = toDouble(center['latitude']);
        centerLng = toDouble(center['longitude']);
      }
    }
    final latValue = json['latitude'] ?? json['lat'] ?? json['driver_latitude'] ?? json['driver_lat'];
    final lngValue = json['longitude'] ?? json['lng'] ?? json['driver_longitude'] ?? json['driver_lng'];
    final addressValue = json['location_address'] ?? json['address'] ?? json['location'];
    final branchName = json['branch_name']?.toString();
    final totalOrdersRaw = json['total_orders'] ?? json['totalOrders'];
    return DriverProfile(
      id: (idValue is num) ? idValue.toInt() : int.tryParse(idValue?.toString() ?? '0') ?? 0,
      name: (json['name'] ?? '').toString(),
      image: json['image']?.toString(),
      status: (json['status'] ?? 'Unknown').toString(),
      mobile: json['mobile']?.toString(),
      nationality: json['nationality']?.toString(),
      language: json['language']?.toString(),
      branchName: branchName,
      totalOrders: (totalOrdersRaw is num) ? totalOrdersRaw.toInt() : int.tryParse(totalOrdersRaw?.toString() ?? '0') ?? 0,
      lat: toDouble(latValue),
      lng: toDouble(lngValue),
      locationAddress: addressValue?.toString(),
      mapboxToken: mapbox?['public_token']?.toString(),
      mapboxStyle: mapbox?['style']?.toString(),
      mapboxCenterLat: centerLat,
      mapboxCenterLng: centerLng,
      mapboxZoom: toDouble(mapbox?['zoom']),
      updatedAt: json['updated_at']?.toString() ?? json['updatedAt']?.toString(),
      payrollEnabled: _featureBool(json, 'payroll_enabled'),
      chatEnabled:    _featureBool(json, 'chat_enabled'),
      callsEnabled:   _featureBool(json, 'calls_enabled'),
    );
  }

  static bool _featureBool(Map<String, dynamic> json, String key) {
    final features = json['features'];
    if (features is Map<String, dynamic>) {
      final v = features[key];
      return v == true || v == 1 || v == '1' || v == 'true';
    }
    return true; // default on if not provided
  }
}
