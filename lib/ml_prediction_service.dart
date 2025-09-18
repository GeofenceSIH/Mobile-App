// lib/ml_prediction_service.dart
// Handles all HTTP calls to the FastAPI ML backend.

import 'dart:convert';
import 'package:http/http.dart' as http;

class MLPredictionService {
  // Change this to your backend URL or keep localhost for emulator tests.
  static const String _baseUrl = 'http://127.0.0.1:8000';

  /// Landslide-risk prediction
  static Future<Map<String, dynamic>?> predictLandslide({
    required double latitude,
    required double longitude,
    double radius = 5000,
    int timeHorizon = 24,
  }) async {
    final url = Uri.parse('$_baseUrl/api/v1/predict/risk');
    final body = {
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'prediction_type': 'landslide',
      'time_horizon': timeHorizon,
    };

    return _post(url, body);
  }

  /// Flood-risk prediction
  static Future<Map<String, dynamic>?> predictFlood({
    required Map<String, double> areaBounds,
    int predictionHours = 24,
  }) async {
    final url = Uri.parse('$_baseUrl/api/v1/predict/risk');
    final body = {
      'area_bounds': areaBounds,
      'prediction_type': 'flood',
      'prediction_hours': predictionHours,
    };

    return _post(url, body);
  }

  /// Weather-risk prediction
  static Future<Map<String, dynamic>?> predictWeatherRisk({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
  }) async {
    final url = Uri.parse('$_baseUrl/api/v1/predict/risk');
    final body = {
      'latitude': latitude,
      'longitude': longitude,
      'prediction_type': 'weather',
      'forecast_days': forecastDays,
    };

    return _post(url, body);
  }

  /// Helper for POST requests
  static Future<Map<String, dynamic>?> _post(
      Uri url, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      // ignore: avoid_print
      print('ML API error: $e');
    }
    return null;
  }
}
