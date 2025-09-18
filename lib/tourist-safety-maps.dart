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
import 'package:flutter/services.dart'; // Add this for Clipboard
import 'offline_service.dart';
import 'profile_page.dart';
import 'dart:math';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:vibration/vibration.dart'; // Add this dependency

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
  final MapController _mapController = MapController();

  late AnimationController _pulseController;


  // Location and map state
  Position? currentPosition;
  String currentAddress = '';
  StreamSubscription<Position>? positionStream;
  List<Marker> markers = [];
  List<CircleMarker> riskCircles = [];

  // Safety data
  List<RiskArea> riskAreas = [];
  List<EmergencyContact> emergencyContacts = [];
  String? userBlockchainId;
  bool isTrackingEnabled = true;
  bool isInRiskZone = false;

  // Enhanced notification state
  Map<String, DateTime> lastAlertTimes = {}; // Prevent spam notifications
  Set<String> acknowledgedRiskZones = {}; // Track acknowledged alerts
  Timer? riskEscalationTimer;
  String? currentRiskZoneId;

  // Tourist data
  Map<String, dynamic>? touristProfile;
  String currentRiskLevel = 'SAFE';
  DateTime? lastLocationUpdate;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _configureFCM();
    _initializeOfflineService();

  }

  Future<void> _initializeOfflineService() async {
    try {
      OfflineService offlineService = OfflineService();
      await offlineService.initialize();

      // Add emergency contacts
      await offlineService.addEmergencyContact(
        id: 'emergency_1',
        name: 'Emergency Contact',
        phone: '+1234567890',
        relationship: 'Family',
        priority: 1,
      );

      // Set user's phone number
      await offlineService.setUserPhoneNumber('+1987654321');

      print('✅ Offline service initialized in SafetyDashboard');
    } catch (e) {
      print('❌ Error initializing offline service: $e');
    }
  }


  void _configureFCM() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // For emergency notifications
    );

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    String? token = await FirebaseMessaging.instance.getToken();
    print('FCM Token: $token');

    await _saveTokenToFirestore(token);

    // Enhanced foreground message handling
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });
  }

  // Add this method to your _SafetyDashboardState class
  Future<void> _testNotificationSystem() async {
    print('🧪 Testing notification system...');

    // Test basic notification
    await _sendEnhancedNotification(
      title: 'Test Notification',
      body: 'If you see this, your notification system is working!',
      type: NotificationType.general,
    );

    // Test with delay (5 seconds)
    Timer(const Duration(seconds: 5), () async {
      await _sendEnhancedNotification(
        title: 'Delayed Test',
        body: 'This notification was sent 5 seconds after the first one.',
        type: NotificationType.moderateRisk,
      );
    });

    // Test high priority notification
    Timer(const Duration(seconds: 10), () async {
      await _sendEnhancedNotification(
        title: '🚨 Priority Test',
        body: 'This is a high-priority notification with vibration.',
        type: NotificationType.emergency,
        data: {
          'test': 'true',
          'action': 'acknowledge_risk',
        },
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test notifications sent! Check your notification panel.'),
        duration: Duration(seconds: 3),
      ),
    );
  }


  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return;

    final String userId = await _getUserId();
    try {
      await firestore.collection('users').doc(userId).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        'deviceInfo': {
          'platform': Theme.of(context).platform.name,
          'appVersion': '1.0.0',
        }
      }, SetOptions(merge: true));
      print('FCM Token saved to Firestore');
    } catch (e) {
      print('Error saving FCM token to Firestore: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      // Determine notification type from data
      String notificationType = message.data['type'] ?? 'general';

      _sendEnhancedNotification(
        title: notification.title ?? 'Safety Alert',
        body: notification.body ?? '',
        type: _getNotificationTypeFromString(notificationType),
        data: message.data,
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    // Handle what happens when user taps notification
    String? action = message.data['action'];

    switch (action) {
      case 'view_risk_zone':
        _navigateToRiskZone(message.data['risk_zone_id']);
        break;
      case 'emergency_contact':
        _showEmergencyDialog();
        break;
      default:
      // Default action - maybe show a detailed alert dialog
        break;
    }
  }

  Future<void> _initializeApp() async {
    await _initializeEnhancedNotifications();
    await _requestLocationPermissions();
    await _getCurrentLocation();
    await _loadSafetyData();
    _startLocationTracking();
  }

  Future<void> _initializeEnhancedNotifications() async {
    // Android notification channels - REMOVED priority parameter
    const List<AndroidNotificationChannel> channels = [
      AndroidNotificationChannel(
        'emergency_channel',
        'Emergency Alerts',
        description: 'Critical emergency notifications',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
      AndroidNotificationChannel(
        'high_risk_channel',
        'High Risk Alerts',
        description: 'High risk zone notifications',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'moderate_risk_channel',
        'Risk Alerts',
        description: 'Moderate risk zone notifications',
        importance: Importance.defaultImportance,
        playSound: true,
      ),
      AndroidNotificationChannel(
        'safety_updates_channel',
        'Safety Updates',
        description: 'General safety information',
        importance: Importance.low,
      ),
    ];

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Create channels
    for (final channel in channels) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }


  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      Map<String, dynamic> data = json.decode(response.payload!);

      switch (data['action']) {
        case 'acknowledge_risk':
          _acknowledgeRiskZone(data['risk_zone_id']);
          break;
        case 'call_emergency':
          _initiateEmergencyCall();
          break;
        case 'im_safe':
          _markUserSafe();
          break;
        case 'get_directions':
          _showDirectionsToSafety();
          break;
      }
    }
  }

  Future<void> _updateUserLocation(Position position) async {
    try {
      String? fcmToken = await messaging.getToken();
      final String userId = await _getUserId();

      await firestore.collection('user_locations').doc(userId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'fcmToken': fcmToken,
        'lastUpdated': FieldValue.serverTimestamp(),
        'riskStatus': currentRiskLevel,
        'isInRiskZone': isInRiskZone,
      }, SetOptions(merge: true));

      print('User location updated in Firestore');
    } catch (e) {
      print('Error updating user location: $e');
    }
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
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
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
      distanceFilter: 5, // Reduced for better risk zone detection
    );
    positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      setState(() {
        currentPosition = position;
        lastLocationUpdate = DateTime.now();
      });
      await _updateAddress(position);
      await _checkRiskZonesEnhanced(position);
      await _updateUserLocation(position);
      _updateMapMarker();
    });
  }

  Future<void> _loadSafetyData() async {
    print("🔥 Loading risk areas from Firestore...");

    riskAreasSubscription = firestore
        .collection('risk_areas')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      print("🔥 Risk areas updated: ${snapshot.docs.length} areas");

      setState(() {
        riskAreas = snapshot.docs.map((doc) {
          var data = doc.data();
          return RiskArea(
            id: doc.id,
            name: data['name'] ?? 'Unnamed',
            description: data['description'] ?? '',
            riskLevel: data['risk_level'] ?? 'MODERATE',
            latitude: data['latitude']?.toDouble() ?? 0.0,
            longitude: data['longitude']?.toDouble() ?? 0.0,
            radius: data['radius']?.toDouble() ?? 200.0,
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
    riskCircles = riskAreas.map((area) =>
        CircleMarker(
          point: LatLng(area.latitude, area.longitude),
          color: _getRiskAreaColor(area.riskLevel).withOpacity(0.3),
          borderStrokeWidth: 3,
          borderColor: _getRiskAreaColor(area.riskLevel),
          useRadiusInMeter: true,
          radius: area.radius,
        ),
    ).toList();

    _updateMapMarker();
  }

  Color _getRiskAreaColor(String riskLevel) {
    switch (riskLevel.toUpperCase()) {
      case 'LOW':
        return Colors.yellow;
      case 'MODERATE':
        return Colors.orange;
      case 'HIGH':
        return Colors.red;
      case 'EMERGENCY':
        return Colors.brown;
      default:
        return Colors.lightGreen;
    }
  }

  void _updateMapMarker() {
    if (currentPosition != null) {
      markers.clear();

      // Current location marker with risk status
      markers.add(Marker(
        point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        width: 50,
        height: 50,
        key: const ValueKey('current_location'),
        child: Container(
          decoration: BoxDecoration(
            color: isInRiskZone ? _getRiskLevelColor(currentRiskLevel) : Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Icon(
            isInRiskZone ? Icons.warning : Icons.person,
            color: Colors.white,
            size: 24,
          ),
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

  Future<void> _checkRiskZonesEnhanced(Position position) async {
    bool inRiskZone = false;
    String detectedRiskLevel = 'SAFE';
    RiskArea? currentRiskArea;

    // Check all risk areas
    for (RiskArea area in riskAreas) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        area.latitude,
        area.longitude,
      );

      if (distance <= area.radius) {
        inRiskZone = true;
        detectedRiskLevel = area.riskLevel;
        currentRiskArea = area;

        // Handle risk zone entry
        if (!isInRiskZone || currentRiskZoneId != area.id) {
          await _handleRiskZoneEntry(area, distance);
        }
        break; // Use the first (closest or most severe) risk area found
      }
    }

    // Handle risk zone exit
    if (!inRiskZone && isInRiskZone) {
      await _handleRiskZoneExit();
    }

    setState(() {
      isInRiskZone = inRiskZone;
      currentRiskLevel = detectedRiskLevel;
      currentRiskZoneId = currentRiskArea?.id;
    });
  }

  Future<void> _handleRiskZoneEntry(RiskArea area, double distance) async {
    print('🚨 Entered risk zone: ${area.name} (${area.riskLevel})');

    // Prevent spam notifications (minimum 5 minutes between alerts for same zone)
    String alertKey = 'risk_${area.id}';
    DateTime now = DateTime.now();

    if (lastAlertTimes.containsKey(alertKey)) {
      Duration timeSinceLastAlert = now.difference(lastAlertTimes[alertKey]!);
      if (timeSinceLastAlert.inMinutes < 5 && !acknowledgedRiskZones.contains(area.id)) {
        return; // Don't send duplicate notifications
      }
    }

    lastAlertTimes[alertKey] = now;

    // Send appropriate notification based on risk level
    await _sendRiskZoneNotification(area, distance);

    // Start escalation timer for high-risk areas
    if (area.riskLevel == 'HIGH' || area.riskLevel == 'EMERGENCY') {
      _startRiskEscalationTimer(area);
    }

    // Send to Firebase for server-side processing
    await _notifyServerOfRiskZoneEntry(area);
  }

  Future<void> _handleRiskZoneExit() async {
    print('✅ Exited risk zone');

    // Cancel escalation timer
    riskEscalationTimer?.cancel();

    // Send exit notification
    await _sendEnhancedNotification(
      title: 'Risk Zone Exited',
      body: 'You have safely exited the risk zone. Stay alert and continue monitoring.',
      type: NotificationType.general,
    );

    // Clear acknowledged zones
    acknowledgedRiskZones.clear();
  }

  Future<void> _sendRiskZoneNotification(RiskArea area, double distance) async {
    String title;
    String body;
    NotificationType type;

    switch (area.riskLevel.toUpperCase()) {
      case 'EMERGENCY':
        title = '🚨 EMERGENCY ALERT';
        body = 'IMMEDIATE DANGER: You have entered ${area.name}. Evacuate immediately!';
        type = NotificationType.emergency;

        // ENHANCED VIGOROUS VIBRATION FOR EMERGENCY
        if (await Vibration.hasVibrator() ?? false) {
          // Long aggressive pattern - 10 seconds of intense vibration
          Vibration.vibrate(pattern: [
            0, 1000, 200, 1000, 200, 1000, 200, 1000, 200, 1000,
            200, 800, 200, 800, 200, 800, 200, 600, 200, 600
          ]);

          // Alternative: Continuous vibration for 5 seconds
          // Vibration.vibrate(duration: 5000);
        }
        break;

      case 'HIGH':
        title = '⚠ HIGH RISK ALERT';
        body = 'HIGH RISK: You have entered ${area.name}. Exercise extreme caution.';
        type = NotificationType.highRisk;

        // VIGOROUS VIBRATION FOR HIGH RISK
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(pattern: [0, 800, 300, 800, 300, 800, 300, 600]);
        }
        break;

      case 'MODERATE':
        title = '⚠ Risk Zone Alert';
        body = 'You have entered a moderate risk area: ${area.name}. Stay vigilant.';
        type = NotificationType.moderateRisk;

        // MODERATE VIBRATION
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
        }
        break;

      default:
        title = 'Safety Notice';
        body = 'You have entered ${area.name}. Please be aware of your surroundings.';
        type = NotificationType.general;

        // LIGHT VIBRATION
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 800);
        }
        break;
    }

    // Add distance and description to body
    body += '\n\nDistance: ${distance.round()}m';
    if (area.description.isNotEmpty) {
      body += '\n${area.description}';
    }

    // Send the enhanced notification with vibration
    await _sendEnhancedNotification(
      title: title,
      body: body,
      type: type,
      data: {
        'risk_zone_id': area.id,
        'risk_level': area.riskLevel,
        'action': 'acknowledge_risk',
      },
    );
  }


  Future<void> _sendEnhancedNotification({
    required String title,
    required String body,
    required NotificationType type,
    Map<String, dynamic>? data,
  }) async {
    // Determine notification channel and settings based on type
    String channelId;
    Importance importance;
    Priority priority;
    bool ongoing = false;
    List<AndroidNotificationAction> actions = [];

    switch (type) {
      case NotificationType.emergency:
        channelId = 'emergency_channel';
        importance = Importance.max;
        priority = Priority.max; // Use Priority.max instead of Priority.high
        ongoing = true;
        actions = [
          const AndroidNotificationAction('call_emergency', 'Call 911', showsUserInterface: true),
          const AndroidNotificationAction('im_safe', 'I\'m Safe'),
        ];
        break;

      case NotificationType.highRisk:
        channelId = 'high_risk_channel';
        importance = Importance.high;
        priority = Priority.high;
        actions = [
          const AndroidNotificationAction('acknowledge_risk', 'Acknowledge'),
          const AndroidNotificationAction('get_directions', 'Get Directions'),
        ];
        break;

      case NotificationType.moderateRisk:
        channelId = 'moderate_risk_channel';
        importance = Importance.defaultImportance;
        priority = Priority.defaultPriority;
        actions = [
          const AndroidNotificationAction('acknowledge_risk', 'Acknowledge'),
        ];
        break;

      default:
        channelId = 'safety_updates_channel';
        importance = Importance.low;
        priority = Priority.low;
        break;
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _getChannelName(channelId),
      channelDescription: _getChannelDescription(channelId),
      importance: importance,
      priority: priority, // Priority goes here in AndroidNotificationDetails
      ongoing: ongoing,
      autoCancel: !ongoing,
      actions: actions,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Tourist Safety Tracker',
      ),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: type == NotificationType.emergency ? 'emergency_sound.wav' : null,
      interruptionLevel: type == NotificationType.emergency
          ? InterruptionLevel.critical
          : InterruptionLevel.active,
    );

    final platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformDetails,
      payload: data != null ? json.encode(data) : null,
    );
  }

  void _startRiskEscalationTimer(RiskArea area) {
    riskEscalationTimer?.cancel();

    // Send escalating alerts every 2 minutes if user hasn't acknowledged
    riskEscalationTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (!acknowledgedRiskZones.contains(area.id)) {
        _sendEscalationNotification(area, timer.tick);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _sendEscalationNotification(RiskArea area, int escalationLevel) async {
    String title = '🚨 ESCALATED ALERT #$escalationLevel';
    String body = 'You are still in ${area.name}. Please acknowledge this alert or seek immediate assistance.';

    await _sendEnhancedNotification(
      title: title,
      body: body,
      type: NotificationType.emergency,
      data: {
        'risk_zone_id': area.id,
        'escalation_level': escalationLevel,
        'action': 'acknowledge_risk',
      },
    );

    // ENHANCED ESCALATION VIBRATION - Gets more intense with each escalation
    if (await Vibration.hasVibrator() ?? false) {
      List<int> pattern = [];

      // Create increasingly intense pattern
      for (int i = 0; i < escalationLevel * 3; i++) {
        pattern.addAll([0, 800, 200]);
      }

      // Add final long vibration
      pattern.addAll([0, 2000]);

      await Vibration.vibrate(pattern: pattern);
    }
  }


  Future<void> _notifyServerOfRiskZoneEntry(RiskArea area) async {
    try {
      final String userId = await _getUserId();

      await firestore.collection('risk_zone_entries').add({
        'userId': userId,
        'riskZoneId': area.id,
        'riskZoneName': area.name,
        'riskLevel': area.riskLevel,
        'entryTime': FieldValue.serverTimestamp(),
        'location': GeoPoint(currentPosition!.latitude, currentPosition!.longitude),
        'acknowledged': false,
      });

      // This could trigger server-side logic to:
      // - Notify emergency contacts
      // - Alert authorities for high-risk zones
      // - Send push notifications to other users in the area

    } catch (e) {
      print('Error notifying server of risk zone entry: $e');
    }
  }

  // Notification action handlers
  void _acknowledgeRiskZone(String riskZoneId) {
    acknowledgedRiskZones.add(riskZoneId);
    riskEscalationTimer?.cancel();

    // Update server
    _updateRiskZoneAcknowledgment(riskZoneId);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Risk zone alert acknowledged')),
    );
  }

  void _initiateEmergencyCall() {
    // Implement emergency calling logic
    _showEmergencyDialog();
  }

  void _markUserSafe() {
    setState(() {
      isInRiskZone = false;
      currentRiskLevel = 'SAFE';
    });

    // Notify server that user marked themselves safe
    _notifyServerUserSafe();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as safe. Stay vigilant!')),
    );
  }

  void _showDirectionsToSafety() {
    // Implement directions to nearest safe zone
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Directions to Safety'),
        content: const Text('Opening directions to the nearest safe area...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Utility methods
  Future<String> _getUserId() async {
    // Implement your user ID logic
    String? userId = await secureStorage.read(key: 'user_id');
    return userId ?? 'anonymous_user';
  }

  NotificationType _getNotificationTypeFromString(String type) {
    switch (type.toLowerCase()) {
      case 'emergency':
        return NotificationType.emergency;
      case 'high_risk':
        return NotificationType.highRisk;
      case 'moderate_risk':
        return NotificationType.moderateRisk;
      default:
        return NotificationType.general;
    }
  }

  String _getChannelName(String channelId) {
    switch (channelId) {
      case 'emergency_channel':
        return 'Emergency Alerts';
      case 'high_risk_channel':
        return 'High Risk Alerts';
      case 'moderate_risk_channel':
        return 'Risk Alerts';
      default:
        return 'Safety Updates';
    }
  }

  String _getChannelDescription(String channelId) {
    switch (channelId) {
      case 'emergency_channel':
        return 'Critical emergency notifications requiring immediate attention';
      case 'high_risk_channel':
        return 'High risk zone notifications';
      case 'moderate_risk_channel':
        return 'Moderate risk zone notifications';
      default:
        return 'General safety information and updates';
    }
  }

  Future<void> _updateRiskZoneAcknowledgment(String riskZoneId) async {
    try {
      final String userId = await _getUserId();

      // Update the most recent entry for this user and risk zone
      QuerySnapshot entries = await firestore
          .collection('risk_zone_entries')
          .where('userId', isEqualTo: userId)
          .where('riskZoneId', isEqualTo: riskZoneId)
          .orderBy('entryTime', descending: true)
          .limit(1)
          .get();

      if (entries.docs.isNotEmpty) {
        await entries.docs.first.reference.update({
          'acknowledged': true,
          'acknowledgedTime': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error updating risk zone acknowledgment: $e');
    }
  }

  Future<void> _notifyServerUserSafe() async {
    try {
      final String userId = await _getUserId();

      await firestore.collection('user_safety_status').doc(userId).set({
        'status': 'safe',
        'lastUpdated': FieldValue.serverTimestamp(),
        'location': GeoPoint(currentPosition!.latitude, currentPosition!.longitude),
        'manuallyMarked': true,
      }, SetOptions(merge: true));

    } catch (e) {
      print('Error notifying server user is safe: $e');
    }
  }

  void _navigateToRiskZone(String? riskZoneId) {
    if (riskZoneId != null) {
      // Find and focus on the specific risk zone
      RiskArea? area = riskAreas.firstWhere(
            (area) => area.id == riskZoneId,
        orElse: () => riskAreas.first,
      );

      // You could add map navigation logic here
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Risk Zone: ${area.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Risk Level: ${area.riskLevel}'),
              const SizedBox(height: 8),
              Text('Description: ${area.description}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
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
            icon: const Icon(Icons.account_circle, size: 24),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
          ),
          IconButton(
              icon: const Icon(Icons.emergency),
              onPressed: _showEmergencyDialog
          ),
        ],
      ),
      body: Column(
        children: [
          // Enhanced Status Bar
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
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      isInRiskZone ? Icons.warning : Icons.shield,
                      color: _getRiskLevelColor(currentRiskLevel),
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
                              color: _getRiskLevelColor(currentRiskLevel),
                            ),
                          ),
                          Text(
                            currentAddress.isNotEmpty ? currentAddress : 'Loading location...',
                            style: const TextStyle(fontSize: 12),
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

                // Show acknowledged risk zones
                if (acknowledgedRiskZones.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Acknowledged alerts: ${acknowledgedRiskZones.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[600],
                      ),
                    ),
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
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                CircleLayer(circles: riskCircles),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),

          // Enhanced Bottom Info Panel
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
                _buildInfoCard('Tracking', isTrackingEnabled ? 'ON' : 'OFF', Icons.location_on, isTrackingEnabled ? Colors.green : Colors.grey),
                GestureDetector(
                  onTap: _showEmergencyDialog,
                  child: _buildInfoCard('Emergency', 'SOS', Icons.phone, Colors.red),
                ),
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
        return Colors.yellow;
      case 'MODERATE':
        return Colors.orange;
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
    riskEscalationTimer?.cancel();
    super.dispose();
  }
}

// Background message handler (must be top-level function)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');

  // Handle background notifications here
  // This could include updating local storage, triggering local notifications, etc.
}

// Enhanced Data Models
class RiskArea {
  final String id;
  final String name;
  final String description;
  final String riskLevel;
  final double latitude;
  final double longitude;
  final double radius;
  final bool active;
  final String zoneType; // NEW: Add zone type
  final bool aiGenerated;

  RiskArea({
    required this.id,
    required this.name,
    required this.description,
    required this.riskLevel,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.active,
    this.zoneType = 'RISK', // NEW: Default to RISK
    this.aiGenerated = false,
  });
}

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String relationship;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.relationship,
  });
}

// Enhanced notification types
enum NotificationType {
  emergency,
  highRisk,
  moderateRisk,
  general,
}