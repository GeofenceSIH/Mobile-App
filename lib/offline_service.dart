import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:another_telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  // Core services
  late Database _database;
  final Telephony _telephony = Telephony.instance;
  final Connectivity _connectivity = Connectivity(); // Fixed: Remove .instance

  // State management
  bool _isOffline = false;
  bool _isTrackingOffline = false;
  StreamSubscription<Position>? _offlineLocationStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivityStream; // Fixed: List<ConnectivityResult>
  Timer? _offlineCheckTimer;

  // Emergency contacts for SMS
  List<String> _emergencyNumbers = [];
  String? _userPhoneNumber;

  // Offline data storage
  static const String _offlineRiskAreasKey = 'offline_risk_areas';
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _offlineEntriesKey = 'offline_risk_entries';

  /// Initialize the offline service
  Future<void> initialize() async {
    await _initializeDatabase();
    await _requestPermissions();
    await _setupTelephony();
    await _loadEmergencyContacts();
    _startConnectivityMonitoring();
    await _syncRiskAreasForOffline();

    print('🔄 Offline Service initialized successfully');
  }

  /// Initialize SQLite database for offline storage
  Future<void> _initializeDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'offline_safety.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        // Risk areas table
        await db.execute('''
          CREATE TABLE risk_areas (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            risk_level TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            radius REAL NOT NULL,
            active INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');

        // Offline location tracking table
        await db.execute('''
          CREATE TABLE offline_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp INTEGER NOT NULL,
            risk_level TEXT,
            synced INTEGER DEFAULT 0
          )
        ''');

        // Risk zone entries while offline
        await db.execute('''
          CREATE TABLE offline_risk_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            risk_area_id TEXT NOT NULL,
            risk_area_name TEXT NOT NULL,
            risk_level TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            entry_time INTEGER NOT NULL,
            sms_sent INTEGER DEFAULT 0,
            synced INTEGER DEFAULT 0
          )
        ''');

        // Emergency contacts
        await db.execute('''
          CREATE TABLE emergency_contacts (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            relationship TEXT,
            priority INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE offline_locations ADD COLUMN risk_level TEXT');
        }
      },
    );
  }

  /// Request all necessary permissions for offline functionality
  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> permissions = await [
      Permission.locationAlways,
      Permission.sms,
      Permission.phone,
      Permission.storage,
      Permission.notification,
    ].request();

    // Check if critical permissions are granted
    if (permissions[Permission.locationAlways] != PermissionStatus.granted) {
      throw Exception('Location permission is required for offline tracking');
    }

    if (permissions[Permission.sms] != PermissionStatus.granted) {
      print('⚠️ SMS permission not granted - SMS alerts will not work');
    }

    print('✅ Permissions granted for offline service');
  }

  /// Setup telephony for SMS functionality
  Future<void> _setupTelephony() async {
    try {
      bool? result = await _telephony.requestPhoneAndSmsPermissions;
      if (result ?? false) {
        print('✅ Telephony permissions granted');
      } else {
        print('❌ Telephony permissions denied');
      }
    } catch (e) {
      print('Error setting up telephony: $e');
    }
  }

  /// Load emergency contacts from database
  Future<void> _loadEmergencyContacts() async {
    try {
      final List<Map<String, dynamic>> contacts = await _database.query('emergency_contacts');
      _emergencyNumbers = contacts.map((contact) => contact['phone'] as String).toList();

      // Load user's own number for identification
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _userPhoneNumber = prefs.getString('user_phone_number');

      print('📱 Loaded ${_emergencyNumbers.length} emergency contacts');
    } catch (e) {
      print('Error loading emergency contacts: $e');
    }
  }

  /// Add emergency contact
  Future<void> addEmergencyContact({
    required String id,
    required String name,
    required String phone,
    String? relationship,
    int priority = 0,
  }) async {
    await _database.insert(
      'emergency_contacts',
      {
        'id': id,
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'priority': priority,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _loadEmergencyContacts();
    print('✅ Emergency contact added: $name');
  }

  /// Set user's phone number
  Future<void> setUserPhoneNumber(String phoneNumber) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone_number', phoneNumber);
    _userPhoneNumber = phoneNumber;
  }

  /// Start monitoring connectivity status
  void _startConnectivityMonitoring() {
    // Fixed: Handle List<ConnectivityResult> instead of single ConnectivityResult
    _connectivityStream = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      bool wasOffline = _isOffline;
      _isOffline = results.contains(ConnectivityResult.none); // Fixed: Check if list contains none

      if (wasOffline && !_isOffline) {
        // Coming back online - sync data
        _handleComingOnline();
      } else if (!wasOffline && _isOffline) {
        // Going offline - start offline mode
        _handleGoingOffline();
      }
    });

    // Initial connectivity check
    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    // Fixed: Handle List<ConnectivityResult> return type
    List<ConnectivityResult> results = await _connectivity.checkConnectivity();
    _isOffline = results.contains(ConnectivityResult.none);

    if (_isOffline) {
      _handleGoingOffline();
    }
  }

  /// Handle transition to offline mode
  void _handleGoingOffline() {
    print('📴 Going offline - starting offline tracking');
    _startOfflineLocationTracking();
  }

  /// Handle transition to online mode
  void _handleComingOnline() async {
    print('📶 Coming back online - syncing data');
    _stopOfflineLocationTracking();
    await _syncOfflineData();
    await _syncRiskAreasForOffline();
  }

  /// Start offline location tracking
  void _startOfflineLocationTracking() {
    if (_isTrackingOffline) return;

    _isTrackingOffline = true;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _offlineLocationStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      await _handleOfflineLocationUpdate(position);
    });

    print('🗺️ Started offline location tracking');
  }

  /// Stop offline location tracking
  void _stopOfflineLocationTracking() {
    _isTrackingOffline = false;
    _offlineLocationStream?.cancel();
    _offlineLocationStream = null;
    print('🛑 Stopped offline location tracking');
  }

  /// Handle location updates while offline
  Future<void> _handleOfflineLocationUpdate(Position position) async {
    try {
      await _storeOfflineLocation(position);
      String riskLevel = await _checkOfflineRiskZones(position);

      await _database.rawUpdate('''
        UPDATE offline_locations 
        SET risk_level = ? 
        WHERE id = (SELECT MAX(id) FROM offline_locations)
      ''', [riskLevel]);

      print('📍 Offline location updated: ${position.latitude}, ${position.longitude} - Risk: $riskLevel');

    } catch (e) {
      print('Error handling offline location: $e');
    }
  }

  /// Store location data offline
  Future<void> _storeOfflineLocation(Position position) async {
    await _database.insert('offline_locations', {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    });
  }

  /// Check risk zones using offline data
  Future<String> _checkOfflineRiskZones(Position position) async {
    try {
      final List<Map<String, dynamic>> riskAreas = await _database.query(
        'risk_areas',
        where: 'active = ?',
        whereArgs: [1],
      );

      String highestRiskLevel = 'SAFE';
      String? triggeredRiskAreaId;
      String? triggeredRiskAreaName;

      for (Map<String, dynamic> area in riskAreas) {
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          area['latitude'],
          area['longitude'],
        );

        if (distance <= area['radius']) {
          String riskLevel = area['risk_level'];

          int riskPriority = _getRiskPriority(riskLevel);
          int currentPriority = _getRiskPriority(highestRiskLevel);

          if (riskPriority > currentPriority) {
            highestRiskLevel = riskLevel;
            triggeredRiskAreaId = area['id'];
            triggeredRiskAreaName = area['name'];
          }
        }
      }

      if (highestRiskLevel != 'SAFE' && triggeredRiskAreaId != null) {
        await _handleOfflineRiskZoneEntry(
          position,
          triggeredRiskAreaId,
          triggeredRiskAreaName!,
          highestRiskLevel,
        );
      }

      return highestRiskLevel;

    } catch (e) {
      print('Error checking offline risk zones: $e');
      return 'SAFE';
    }
  }

  /// Get risk priority for comparison
  int _getRiskPriority(String riskLevel) {
    switch (riskLevel.toUpperCase()) {
      case 'EMERGENCY':
        return 4;
      case 'HIGH':
        return 3;
      case 'MODERATE':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  /// Handle entering a risk zone while offline
  Future<void> _handleOfflineRiskZoneEntry(
      Position position,
      String riskAreaId,
      String riskAreaName,
      String riskLevel,
      ) async {
    try {
      int fiveMinutesAgo = DateTime.now().millisecondsSinceEpoch - (5 * 60 * 1000);

      final List<Map<String, dynamic>> recentEntries = await _database.query(
        'offline_risk_entries',
        where: 'risk_area_id = ? AND entry_time > ?',
        whereArgs: [riskAreaId, fiveMinutesAgo],
      );

      if (recentEntries.isNotEmpty) {
        print('🔄 Risk zone entry already recorded recently');
        return;
      }

      int entryId = await _database.insert('offline_risk_entries', {
        'risk_area_id': riskAreaId,
        'risk_area_name': riskAreaName,
        'risk_level': riskLevel,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'entry_time': DateTime.now().millisecondsSinceEpoch,
        'sms_sent': 0,
        'synced': 0,
      });

      print('🚨 OFFLINE: Entered risk zone: $riskAreaName ($riskLevel)');

      await _sendOfflineSMSAlert(riskAreaName, riskLevel, position, entryId);

    } catch (e) {
      print('Error handling offline risk zone entry: $e');
    }
  }

  /// Send SMS alert when entering risk zone offline
  Future<void> _sendOfflineSMSAlert(
      String riskAreaName,
      String riskLevel,
      Position position,
      int entryId,
      ) async {
    if (_emergencyNumbers.isEmpty) {
      print('⚠️ No emergency contacts configured for SMS alerts');
      return;
    }

    try {
      String message = _buildSMSMessage(riskAreaName, riskLevel, position);
      bool allSent = true;

      for (String phoneNumber in _emergencyNumbers) {
        try {
          await _telephony.sendSms(
            to: phoneNumber,
            message: message,
          );
          print('📱 SMS sent to $phoneNumber');
        } catch (e) {
          print('❌ Failed to send SMS to $phoneNumber: $e');
          allSent = false;
        }
      }

      if (allSent) {
        await _database.update(
          'offline_risk_entries',
          {'sms_sent': 1},
          where: 'id = ?',
          whereArgs: [entryId],
        );
        print('✅ All SMS alerts sent successfully');
      }

    } catch (e) {
      print('Error sending offline SMS alert: $e');
    }
  }

  /// Build SMS message for risk zone alert
  String _buildSMSMessage(String riskAreaName, String riskLevel, Position position) {
    String urgencyEmoji;
    String urgencyText;

    switch (riskLevel.toUpperCase()) {
      case 'EMERGENCY':
        urgencyEmoji = '🆘';
        urgencyText = 'EMERGENCY';
        break;
      case 'HIGH':
        urgencyEmoji = '🚨';
        urgencyText = 'HIGH RISK';
        break;
      case 'MODERATE':
        urgencyEmoji = '⚠️';
        urgencyText = 'MODERATE RISK';
        break;
      default:
        urgencyEmoji = '⚠️';
        urgencyText = 'RISK ALERT';
        break;
    }

    String timestamp = DateTime.now().toString().substring(0, 19);
    String locationUrl = 'https://maps.google.com/?q=${position.latitude},${position.longitude}';

    return '''$urgencyEmoji TOURIST SAFETY ALERT $urgencyEmoji

$urgencyText: Tourist has entered dangerous area: $riskAreaName

Time: $timestamp
Location: $locationUrl
Risk Level: $riskLevel

This is an automated safety alert. Tourist may be offline.

- Tourist Safety Tracker''';
  }

  /// Sync offline data when coming back online
  Future<void> _syncOfflineData() async {
    try {
      await _syncOfflineLocations();
      await _syncOfflineRiskEntries();
      print('✅ Offline data synced successfully');
    } catch (e) {
      print('Error syncing offline data: $e');
    }
  }

  /// Sync offline locations to Firestore
  Future<void> _syncOfflineLocations() async {
    try {
      final List<Map<String, dynamic>> unsynced = await _database.query(
        'offline_locations',
        where: 'synced = ?',
        whereArgs: [0],
      );

      FirebaseFirestore firestore = FirebaseFirestore.instance;

      for (Map<String, dynamic> location in unsynced) {
        await firestore.collection('offline_locations').add({
          'userId': await _getUserId(),
          'latitude': location['latitude'],
          'longitude': location['longitude'],
          'timestamp': Timestamp.fromMillisecondsSinceEpoch(location['timestamp']),
          'riskLevel': location['risk_level'],
          'deviceType': 'offline',
        });

        await _database.update(
          'offline_locations',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [location['id']],
        );
      }

      print('📊 Synced ${unsynced.length} offline locations');
    } catch (e) {
      print('Error syncing offline locations: $e');
    }
  }

  /// Sync offline risk entries to Firestore
  Future<void> _syncOfflineRiskEntries() async {
    try {
      final List<Map<String, dynamic>> unsynced = await _database.query(
        'offline_risk_entries',
        where: 'synced = ?',
        whereArgs: [0],
      );

      FirebaseFirestore firestore = FirebaseFirestore.instance;

      for (Map<String, dynamic> entry in unsynced) {
        await firestore.collection('offline_risk_entries').add({
          'userId': await _getUserId(),
          'riskAreaId': entry['risk_area_id'],
          'riskAreaName': entry['risk_area_name'],
          'riskLevel': entry['risk_level'],
          'latitude': entry['latitude'],
          'longitude': entry['longitude'],
          'entryTime': Timestamp.fromMillisecondsSinceEpoch(entry['entry_time']),
          'smsSent': entry['sms_sent'] == 1,
          'offlineMode': true,
        });

        await _database.update(
          'offline_risk_entries',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [entry['id']],
        );
      }

      print('🚨 Synced ${unsynced.length} offline risk entries');
    } catch (e) {
      print('Error syncing offline risk entries: $e');
    }
  }

  /// Download and sync risk areas for offline use
  Future<void> _syncRiskAreasForOffline() async {
    try {
      if (_isOffline) {
        print('⚠️ Currently offline - cannot sync risk areas');
        return;
      }

      FirebaseFirestore firestore = FirebaseFirestore.instance;
      QuerySnapshot snapshot = await firestore
          .collection('risk_areas')
          .where('active', isEqualTo: true)
          .get();

      await _database.delete('risk_areas');

      for (QueryDocumentSnapshot doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        await _database.insert('risk_areas', {
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed',
          'description': data['description'] ?? '',
          'risk_level': data['risk_level'] ?? 'MODERATE',
          'latitude': data['latitude']?.toDouble() ?? 0.0,
          'longitude': data['longitude']?.toDouble() ?? 0.0,
          'radius': data['radius']?.toDouble() ?? 200.0,
          'active': data['active'] == true ? 1 : 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);

      print('🔄 Synced ${snapshot.docs.length} risk areas for offline use');
    } catch (e) {
      print('Error syncing risk areas for offline: $e');
    }
  }

  /// Get all offline risk areas
  Future<List<Map<String, dynamic>>> getOfflineRiskAreas() async {
    return await _database.query(
      'risk_areas',
      where: 'active = ?',
      whereArgs: [1],
    );
  }

  /// Get offline statistics
  Future<Map<String, dynamic>> getOfflineStats() async {
    try {
      final List<Map<String, dynamic>> locationStats = await _database.rawQuery(
          'SELECT COUNT(*) as total, COUNT(CASE WHEN synced = 0 THEN 1 END) as unsynced FROM offline_locations'
      );

      final List<Map<String, dynamic>> riskStats = await _database.rawQuery(
          'SELECT COUNT(*) as total, COUNT(CASE WHEN synced = 0 THEN 1 END) as unsynced FROM offline_risk_entries'
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      int lastSync = prefs.getInt(_lastSyncKey) ?? 0;

      return {
        'isOffline': _isOffline,
        'isTracking': _isTrackingOffline,
        'totalLocations': locationStats.first['total'] ?? 0,
        'unsyncedLocations': locationStats.first['unsynced'] ?? 0,
        'totalRiskEntries': riskStats.first['total'] ?? 0,
        'unsyncedRiskEntries': riskStats.first['unsynced'] ?? 0,
        'lastSyncTime': lastSync,
        'emergencyContacts': _emergencyNumbers.length,
      };
    } catch (e) {
      print('Error getting offline stats: $e');
      return {};
    }
  }

  /// Force start offline tracking (manual override)
  Future<void> forceStartOfflineTracking() async {
    _isOffline = true;
    _startOfflineLocationTracking();
    print('🔧 Force started offline tracking');
  }

  /// Force stop offline tracking
  Future<void> forceStopOfflineTracking() async {
    _stopOfflineLocationTracking();
    print('🔧 Force stopped offline tracking');
  }

  /// Test SMS functionality
  Future<bool> testSMSFunctionality(String testNumber) async {
    try {
      String testMessage = '🧪 TEST: Tourist Safety Tracker SMS functionality test. Time: ${DateTime.now()}';

      await _telephony.sendSms(
        to: testNumber,
        message: testMessage,
      );

      print('✅ Test SMS sent to $testNumber');
      return true;
    } catch (e) {
      print('❌ Test SMS failed: $e');
      return false;
    }
  }

  /// Get user ID (implement based on your authentication system)
  Future<String> _getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'offline_user_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Cleanup resources
  Future<void> dispose() async {
    _offlineLocationStream?.cancel();
    _connectivityStream?.cancel();
    _offlineCheckTimer?.cancel();
    await _database.close();
    print('🧹 Offline service disposed');
  }
}
