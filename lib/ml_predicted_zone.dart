// lib/ml_predicted_zone.dart
// Model representing an AI-predicted risk zone.

class MLPredictedZone {
  final String id;
  final String name;
  final String description;
  final String riskLevel;      // LOW | MODERATE | HIGH | EMERGENCY
  final double latitude;
  final double longitude;
  final double radius;         // in meters
  final String predictionType; // landslide | flood | weather
  final double confidence;     // 0.0 – 1.0
  final DateTime estimatedTime;
  final bool aiGenerated;

  MLPredictedZone({
    required this.id,
    required this.name,
    required this.description,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.predictionType,
    required this.confidence,
    required this.estimatedTime,
    this.aiGenerated = true,
  });

  factory MLPredictedZone.fromJson(Map<String, dynamic> json) {
    return MLPredictedZone(
      id: json['id'] ?? '',
      name: json['name'] ?? 'AI Prediction',
      description: json['description'] ?? '',
      riskLevel: json['risk_level'] ?? 'LOW',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      radius: (json['radius'] as num).toDouble(),
      predictionType: json['prediction_type'] ?? 'general',
      confidence: (json['confidence'] as num).toDouble(),
      estimatedTime: DateTime.parse(json['estimated_time']),
      aiGenerated: json['ai_generated'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'risk_level': riskLevel,
    'lat': latitude,
    'lng': longitude,
    'radius': radius,
    'prediction_type': predictionType,
    'confidence': confidence,
    'estimated_time': estimatedTime.toIso8601String(),
    'ai_generated': aiGenerated,
  };
}
