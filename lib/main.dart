// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sih/risk_area.dart';
import 'tourist-safety-maps.dart' hide RiskArea;
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Obtain initial user position
  Position initialPosition = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  // Fetch manual risk zones from Firestore
  List<RiskArea> manualZones = await _loadManualRiskZones();

  runApp(MyApp(
    initialPosition: initialPosition,
    riskAreas: manualZones,
  ));
}

Future<List<RiskArea>> _loadManualRiskZones() async {
  final firestore = FirebaseFirestore.instance;
  final snapshot = await firestore
      .collection('risk_areas')
      .where('active', isEqualTo: true)
      .get();

  return snapshot.docs.map((doc) {
    final data = doc.data();
    return RiskArea(
      id: doc.id,
      name: data['name'] ?? 'Unnamed',
      riskLevel: data['risk_level'] ?? 'MODERATE',
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      radius: (data['radius'] as num).toDouble(),
    );
  }).toList();
}

class MyApp extends StatelessWidget {
  final Position initialPosition;
  final List<RiskArea> riskAreas;

  const MyApp({
    Key? key,
    required this.initialPosition,
    required this.riskAreas,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tourist Safety App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
      ),
      home: SplashScreen(riskAreas: riskAreas,
        initialPosition: initialPosition,),

    debugShowCheckedModeBanner: false,
    );
  }
}
