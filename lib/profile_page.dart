import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _userName = "Loading...";
  String _userEmail = "Loading...";
  String _touristID = "N/A";
  String _tripDates = "N/A";
  List<String> _itinerary = [];
  List<Map<String, String>> _emergencyContacts = [];
  int _safetyScore = 0;
  bool _geoFencingActive = false;
  bool _trackingOptIn = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    User? user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _userEmail = user.email ?? "No Email";
      });

      DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _userName = userData['name'] ?? "User Name";
          _touristID = userData['touristID'] ?? "N/A";
          _tripDates = userData['tripDates'] ?? "N/A";
          _itinerary = List<String>.from(userData['itinerary'] ?? []);
          _emergencyContacts = List<Map<String, String>>.from(
            (userData['emergencyContacts'] as List<dynamic>?)?.map((e) => Map<String, String>.from(e)) ?? [],
          );
          _safetyScore = userData['safetyScore'] ?? 0;
          _geoFencingActive = userData['geoFencingActive'] ?? false;
          _trackingOptIn = userData['trackingOptIn'] ?? false;
        });
      }
    }
  }

  Future<void> _updateToggle(String field, bool value) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({field: value});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$field updated successfully!')),
      );
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login'); // Assuming you have a login route
    }
  }

  void _showPanicDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Panic Alert'),
          content: const Text('Are you sure you want to send a panic alert to authorities and emergency contacts?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Send Alert', style: TextStyle(color: Colors.white)),
              onPressed: () {
                // Implement panic button logic here
                // e.g., send location to backend, notify emergency contacts
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Panic alert sent!')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.orange.shade700, // Orange part of Indian flag
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Basic Info & Digital ID
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.green.shade700, // Green part of Indian flag
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _userName,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  Text(
                    _userEmail,
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tourist ID: $_touristID',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            const Divider(height: 32, thickness: 1),

            // Trip Itinerary
            _buildSectionTitle('Trip Itinerary'),
            Text(
              _tripDates,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            if (_itinerary.isNotEmpty)
              ..._itinerary.map((place) => Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                child: Text(
                  "- $place",
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
              ))
            else
              const Text("No itinerary planned yet.", style: TextStyle(fontStyle: FontStyle.italic)),
            const Divider(height: 32, thickness: 1),

            // Emergency Contacts
            _buildSectionTitle('Emergency Contacts'),
            if (_emergencyContacts.isNotEmpty)
              ..._emergencyContacts.map(
                    (contact) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  elevation: 1,
                  child: ListTile(
                    leading: const Icon(Icons.contact_phone, color: Colors.orange),
                    title: Text(contact["name"]!, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(contact["phone"]!),
                    trailing: IconButton(
                      icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () {
                        // Implement call functionality
                      },
                    ),
                  ),
                ),
              )
            else
              const Text("No emergency contacts added.", style: TextStyle(fontStyle: FontStyle.italic)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  // Navigate to add/manage emergency contacts
                },
                icon: const Icon(Icons.add, color: Colors.green),
                label: const Text('Add Contact', style: TextStyle(color: Colors.green)),
              ),
            ),
            const Divider(height: 32, thickness: 1),

            // Safety Score
            _buildSectionTitle('Tourist Safety Score'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _safetyScore / 100,
              minHeight: 12,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _safetyScore > 70
                    ? Colors.green.shade700
                    : (_safetyScore > 40 ? Colors.orange.shade700 : Colors.red.shade700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$_safetyScore / 100',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const Divider(height: 32, thickness: 1),

            // Geo-fencing Alerts Toggle
            SwitchListTile(
              title: const Text('Geo-fencing Alerts', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Receive alerts when entering/exiting designated safe zones.'),
              value: _geoFencingActive,
              onChanged: (val) {
                setState(() {
                  _geoFencingActive = val;
                });
                _updateToggle('geoFencingActive', val);
              },
              activeColor: Colors.green.shade700,
            ),
            const SizedBox(height: 8),

            // Real-time Tracking Opt-in
            SwitchListTile(
              title: const Text('Real-time Tracking', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Opt-in for family and authorized personnel tracking for your safety.'),
              value: _trackingOptIn,
              onChanged: (val) {
                setState(() {
                  _trackingOptIn = val;
                });
                _updateToggle('trackingOptIn', val);
              },
              activeColor: Colors.green.shade700,
            ),
            const Divider(height: 32, thickness: 1),

            // Panic Button
            Center(
              child: ElevatedButton.icon(
                onPressed: _showPanicDialog,
                icon: const Icon(Icons.warning, color: Colors.white),
                label: const Text('Panic Button', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700, // Red for panic
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Additional Settings
            _buildSectionTitle('Settings & Information'),
            ListTile(
              leading: const Icon(Icons.language, color: Colors.blueGrey),
              title: const Text('Language Preferences'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                // Navigate to Language settings
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.blueGrey),
              title: const Text('Privacy & Security'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                // Navigate to privacy info
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
              title: const Text('About Us'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                // Navigate to About Us page
              },
            ),
            const Divider(height: 32, thickness: 1),

            // Logout Button
            Center(
              child: TextButton(
                onPressed: _logout,
                child: Text(
                  'Logout',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}