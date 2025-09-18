class RiskArea {
  final String id;
  final double latitude;
  final double longitude;
  final String riskLevel;
  final double radius;
  final String name;
  final String? description;
  final DateTime? createdAt;
  final bool active;
  final bool aiGenerated;

  RiskArea({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.riskLevel,
    required this.radius,
    required this.name,
    this.description,
    this.createdAt,
    this.active = true,
    this.aiGenerated = false,
  });

  factory RiskArea.fromJson(Map<String, dynamic> json) {
    return RiskArea(
      id: json['id'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      riskLevel: json['riskLevel'] ?? 'LOW',
      radius: json['radius']?.toDouble() ?? 100.0,
      name: json['name'] ?? '',
      description: json['description'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      active: json['active'] ?? true,
      aiGenerated: json['aiGenerated'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'riskLevel': riskLevel,
      'radius': radius,
      'name': name,
      'description': description,
      'createdAt': createdAt?.toIso8601String(),
      'active': active,
      'aiGenerated': aiGenerated,
    };
  }
}
