class Vehicle {
  final int? id;
  final String name;
  final String? plateNumber;
  final String? type;
  final String? model;
  final String? color;
  final String? note;

  Vehicle({
    this.id,
    required this.name,
    this.plateNumber,
    this.type,
    this.model,
    this.color,
    this.note,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    String? pickString(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
      return null;
    }

    int? parseId(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    return Vehicle(
      id: parseId(json['id'] ?? json['vehicle_id']),
      name: pickString(['name', 'vehicle_name', 'title', 'label', 'display_name']) ?? 'Vehicle',
      plateNumber: pickString([
        'plate_number',
        'plate',
        'vehicle_number',
        'vehicle_no',
        'registration_number',
        'reg_no',
        'vehicle_plate',
      ]),
      type: pickString(['type', 'vehicle_type', 'category']),
      model: pickString(['model', 'make', 'variant', 'year_model']),
      color: pickString(['color', 'vehicle_color']),
      note: pickString(['note', 'notes', 'description']),
    );
  }
}
