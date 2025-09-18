// lib/tourist_flow_predictor.dart
// Flutter integration for TFLite tourist flow prediction

import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';

class TouristFlowPredictor {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;

  /// Load the TFLite model from assets/models/tourist_flow_model.tflite
  Future<void> loadModel() async {
    if (_isModelLoaded) return;
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/tourist_flow_model.tflite',
      );
      _isModelLoaded = true;
      print('✅ Tourist flow model loaded successfully');
    } catch (e) {
      print('❌ Error loading TFLite model: $e');
    }
  }

  /// Predict tourist flow given a 24×5 sequence of features
  Future<double> predictTouristFlow(List<List<double>> sequenceData) async {
    await loadModel();
    if (_interpreter == null) {
      print('Interpreter not initialized');
      return 0.0;
    }

    // Flatten and prepare input tensor of shape [1, 24, 5]
    final inputBuffer = Float32List(24 * 5);
    int idx = 0;
    for (var row in sequenceData) {
      for (var val in row) {
        inputBuffer[idx++] = val;
      }
    }
    final input = inputBuffer.reshape([1, 24, 5]);

    // Prepare output tensor [1, 1]
    final output = Float32List(1).reshape([1, 1]);

    // Run inference
    _interpreter!.run(input, output);

    return output[0];
  }

  /// Gather the last 24 hours of features for prediction
  Future<List<List<double>>> getCurrentSequenceData() async {
    final now = DateTime.now();
    List<List<double>> sequence = [];

    for (int i = 23; i >= 0; i--) {
      final timePoint = now.subtract(Duration(hours: i));
      final hourNorm = timePoint.hour / 24.0;
      final dayNorm = timePoint.weekday / 7.0;
      final weatherIndex = await getWeatherIndex(timePoint);
      final eventFactor = await getEventFactor(timePoint);
      final seasonalFactor = getSeasonalFactor(timePoint);

      sequence.add([
        hourNorm,
        dayNorm,
        weatherIndex,
        eventFactor,
        seasonalFactor,
      ]);
    }
    return sequence;
  }

  /// Placeholder: Fetch or compute a weather index (0.0–1.0)
  Future<double> getWeatherIndex(DateTime time) async {
    // TODO: Integrate with your weather service or cache
    return 0.8;
  }

  /// Placeholder: Determine event factor (1.0–2.0)
  Future<double> getEventFactor(DateTime time) async {
    // TODO: Check special events calendar
    return 1.0;
  }

  /// Seasonal factor based on peak months
  double getSeasonalFactor(DateTime time) {
    const peakMonths = [6, 7, 8, 12];
    return peakMonths.contains(time.month) ? 1.2 : 1.0;
  }

  /// Dispose the TFLite interpreter when done
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
