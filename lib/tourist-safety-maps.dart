import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';

class SafetyDashboard extends StatefulWidget {
  const SafetyDashboard({super.key});

  @override
  State<SafetyDashboard> createState() => _SafetyDashboardState();
}

class _SafetyDashboardState extends State<SafetyDashboard> {
  final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseMessaging messaging = FirebaseMessaging.instance;
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  StreamSubscription<QuerySnapshot>? riskAreasSubscription;

  // Location and map state
  Position? currentPosition;
  String currentAddress = '';
  StreamSubscription<Position>? positionStream;
  List<Marker> markers = [];
  List<CircleMarker> riskCircles = [];

  // Safety data - REMOVED SafeZone, only RiskArea now
  List<RiskArea> riskAreas = [];
  List<EmergencyContact> emergencyContacts = [];
  String? userBlockchainId;
  bool isTrackingEnabled = true;
  bool isInRiskZone = false; // Changed from isInSafeZone

  // Tourist data
  Map<String, dynamic>? touristProfile;
  String currentRiskLevel = 'SAFE'; // Changed default to SAFE
  DateTime? lastLocationUpdate;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initializeNotifications();
    await _requestLocationPermissions();
    await _getCurrentLocation();
    await _loadSafetyData();
    _startLocationTracking();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await notificationsPlugin.initialize(settings);
  }

  Future<void> _requestLocationPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      _showPermissionDialog();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        currentPosition = position;
      });
      await _updateAddress(position);
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  Future<void> _updateAddress(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          currentAddress = '${place.locality}, ${place.administrativeArea}, ${place.country}';
        });
      }
    } catch (e) {
      print('Error getting address: $e');
    }
  }

  void _startLocationTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      setState(() {
        currentPosition = position;
        lastLocationUpdate = DateTime.now();
      });
      await _updateAddress(position);
      await _checkRiskZones(position); // Updated method name
      _updateMapMarker();
    });
  }

  Future<void> _loadSafetyData() async {
    print("🔥 Loading risk areas from Firestore...");

    // REMOVED safe zones - only listen to risk areas
    riskAreasSubscription = firestore
        .collection('risk_areas')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      print("🔥 Risk areas updated: ${snapshot.docs.length} areas");

      setState(() {
        riskAreas = snapshot.docs.map((doc) {
          var data = doc.data();
          print("📍 Risk area: ${data['name']} - Radius: ${data['radius']}"); // Debug log

          return RiskArea(
            id: doc.id,
            name: data['name'] ?? 'Unnamed',
            description: data['description'] ?? '',
            riskLevel: data['risk_level'] ?? 'MODERATE',
            latitude: data['latitude']?.toDouble() ?? 0.0,
            longitude: data['longitude']?.toDouble() ?? 0.0,
            radius: data['radius']?.toDouble() ?? 200.0, // Added radius support
            active: data['active'] ?? true,
          );
        }).toList();
        _updateMapOverlays();
      });
    }, onError: (error) {
      print("❌ Error loading risk areas: $error");
    });

    emergencyContacts = [];
  }

  void _updateMapOverlays() {
    // Create risk area circles with radius from Firestore
    riskCircles = riskAreas.map((area) =>
        CircleMarker(
          point: LatLng(area.latitude, area.longitude),
          color: _getRiskAreaColor(area.riskLevel).withOpacity(0.3),
          borderStrokeWidth: 3,
          borderColor: _getRiskAreaColor(area.riskLevel),
          useRadiusInMeter: true,
          radius: area.radius, // Use actual radius from Firestore
        ),
    ).toList();

    _updateMapMarker();
  }

  Color _getRiskAreaColor(String riskLevel) {
    switch (riskLevel.toUpperCase()) {
      case 'LOW':
        return Colors.orange;
      case 'MODERATE':
        return Colors.blue;
      case 'HIGH':
        return Colors.red;
      case 'EMERGENCY':
        return Colors.red[900]!;
      default:
        return Colors.grey;
    }
  }

  void _updateMapMarker() {
    if (currentPosition != null) {
      // Clear existing markers
      markers.clear();

      // Current location marker
      markers.add(Marker(
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        width: 50,
        height: 50,
        key: const ValueKey('current_location'),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 24),
        ),
      ));

      // Risk area markers
      for (final area in riskAreas) {
        markers.add(Marker(
          point: LatLng(area.latitude, area.longitude),
          width: 40,
          height: 40,
          child: Icon(
            Icons.warning,
            color: _getRiskAreaColor(area.riskLevel),
            size: 30,
          ),
        ));
      }
    }
    setState(() {});
  }

  Future<void> _checkRiskZones(Position position) async {
    bool inRiskZone = false;
    String detectedRiskLevel = 'SAFE';

    for (RiskArea area in riskAreas) {
      double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          area.latitude,
          area.longitude
      );

      if (distance <= area.radius) {
        inRiskZone = true;
        detectedRiskLevel = area.riskLevel;

        if (!isInRiskZone || currentRiskLevel != area.riskLevel) {
          _sendNotification(
              'Risk Zone Alert',
              'You have entered a ${area.riskLevel} risk area: ${area.name}',
              NotificationType.riskAlert
          );
        }
        break;
      }
    }

    setState(() {
      isInRiskZone = inRiskZone;
      currentRiskLevel = detectedRiskLevel;
    });
  }

  Future<void> _sendNotification(String title, String body, NotificationType type) async {
    const androidDetails = AndroidNotificationDetails(
      'safety_channel', 'Safety Notifications',
      channelDescription: 'Notifications for tourist safety alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const platformDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title, body, platformDetails,
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text('This app needs location permission to provide safety features.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () { Navigator.pop(context); Geolocator.openAppSettings(); }, child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _toggleTracking() {
    setState(() => isTrackingEnabled = !isTrackingEnabled);
    if (isTrackingEnabled) {
      _startLocationTracking();
    } else {
      positionStream?.cancel();
    }
  }

  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency Alert'),
        content: const Text('This will send your current location to emergency services. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Add emergency functionality here
            },
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tourist Safety Tracker'),
        backgroundColor: _getRiskLevelColor(currentRiskLevel),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: Icon(isTrackingEnabled ? Icons.location_on : Icons.location_off),
              onPressed: _toggleTracking
          ),
          IconButton(
              icon: const Icon(Icons.emergency),
              onPressed: _showEmergencyDialog
          ),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getRiskLevelColor(currentRiskLevel).withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: _getRiskLevelColor(currentRiskLevel),
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                    isInRiskZone ? Icons.warning : Icons.shield,
                    color: _getRiskLevelColor(currentRiskLevel)
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Status: ${isInRiskZone ? currentRiskLevel : "SAFE"}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getRiskLevelColor(currentRiskLevel)
                          )
                      ),
                      Text(
                          currentAddress.isNotEmpty ? currentAddress : 'Loading location...',
                          style: const TextStyle(fontSize: 12)
                      ),
                    ],
                  ),
                ),
                if (lastLocationUpdate != null)
                  Text(
                    'Updated: ${_formatTime(lastLocationUpdate!)}',
                    style: const TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: currentPosition == null
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude),
                initialZoom: 16,
                interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),

                // Risk area circles
                CircleLayer(circles: riskCircles),

                // Markers (location + risk area markers)
                MarkerLayer(markers: markers),

                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Info Panel - UPDATED
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCard('Risk Areas', '${riskAreas.length}', Icons.warning, Colors.orange),
                _buildInfoCard('Current Risk', currentRiskLevel, Icons.shield, _getRiskLevelColor(currentRiskLevel)),
                _buildInfoCard('Emergency', 'SOS', Icons.phone, Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Color _getRiskLevelColor(String riskLevel) {
    switch (riskLevel.toUpperCase()) {
      case 'LOW':
        return Colors.orange;
      case 'MODERATE':
        return Colors.blue;
      case 'HIGH':
        return Colors.red;
      case 'EMERGENCY':
        return Colors.red[900]!;
      case 'SAFE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    positionStream?.cancel();
    riskAreasSubscription?.cancel();
    super.dispose();
  }
}

// Updated Data Models
class RiskArea {
  final String id;
  final String name;
  final String description;
  final String riskLevel;
  final double latitude;
  final double longitude;
  final double radius; // Added radius field
  final bool active;

  RiskArea({
    required this.id,
    required this.name,
    required this.description,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.active
  });
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String relationship;

  EmergencyContact({required this.id, required this.name, required this.phone, required this.email, required this.relationship});
}

enum NotificationType {
  riskAlert,
  emergency,
  general,
}
