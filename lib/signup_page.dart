import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';

import 'package:sih/tourist-safety-maps.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> with TickerProviderStateMixin {
  final _aadhaarController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? errorMessage;
  bool isLoading = false;
  bool isSignupComplete = false;

  final secureStorage = const FlutterSecureStorage();

  late AnimationController _formAnimationController;
  late Animation<double> _formFadeAnimation;
  late Animation<Offset> _formSlideAnimation;

  late AnimationController _messageAnimationController;
  late Animation<double> _messageFadeAnimation;
  late Animation<Offset> _messageSlideAnimation;

  @override
  void initState() {
    super.initState();

    _formAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _formFadeAnimation = CurvedAnimation(
      parent: _formAnimationController,
      curve: Curves.easeInOut,
    );

    _formSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(_formFadeAnimation);

    _messageAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _messageFadeAnimation = CurvedAnimation(
      parent: _messageAnimationController,
      curve: Curves.easeInOut,
    );

    _messageSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(_messageFadeAnimation);

    _formAnimationController.forward();
  }

  Future<void> handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      isSignupComplete = false;
    });

    _messageAnimationController.reset();

    try {
      final aadhaar = _aadhaarController.text.trim();
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();

      await Future.delayed(const Duration(seconds: 1));

      final userData = {
        'name': name,
        'phone': phone,
        'aadhaar': '******${aadhaar.substring(6)}',
        'status': 'active',
        'signupDate': DateTime.now().toIso8601String(),
        'lastLogin': DateTime.now().toIso8601String(),
      };

      await secureStorage.write(key: 'aadhaar', value: aadhaar);
      await secureStorage.write(key: 'user_data', value: jsonEncode(userData));
      await secureStorage.write(key: 'is_logged_in', value: 'true');

      setState(() {
        isSignupComplete = true;
        isLoading = false;
      });

      _messageAnimationController.forward();

      await Future.delayed(const Duration(milliseconds: 1500));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const SafetyDashboard(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Signup failed: ${e.toString()}';
        isLoading = false;
      });
      _messageAnimationController.forward();
    }
  }

  @override
  void dispose() {
    _aadhaarController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _formAnimationController.dispose();
    _messageAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Indian tri-color
    const saffron = Color(0xFFFF9933);
    const white = Colors.white;
    const green = Color(0xFF138808);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [saffron, white, green],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: FadeTransition(
                opacity: _formFadeAnimation,
                child: SlideTransition(
                  position: _formSlideAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: saffron,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: saffron.withOpacity(0.5),
                                  blurRadius: 15,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_add_alt_1,
                              size: 48,
                              color: white,
                            ),
                          ),

                          const SizedBox(height: 24),

                          Text(
                            'Join Tourist Safety App',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: green,
                              letterSpacing: 1.2,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Create your account to access safety features',
                            style: TextStyle(
                              fontSize: 16,
                              color: green.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 32),

                          // Name Input
                          _buildInputField(
                            controller: _nameController,
                            label: 'Full Name',
                            icon: Icons.person,
                            keyboardType: TextInputType.name,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your full name';
                              }
                              if (value.trim().length < 2) {
                                return 'Name must be at least 2 characters';
                              }
                              return null;
                            },
                            saffron: saffron,
                            green: green,
                          ),

                          const SizedBox(height: 20),

                          // Phone Input
                          _buildInputField(
                            controller: _phoneController,
                            label: 'Phone Number',
                            icon: Icons.phone,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your phone number';
                              }
                              if (value.length != 10) {
                                return 'Phone number must be 10 digits';
                              }
                              if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                            saffron: saffron,
                            green: green,
                          ),

                          const SizedBox(height: 20),

                          // Aadhaar Input
                          _buildInputField(
                            controller: _aadhaarController,
                            label: 'Aadhaar Number',
                            icon: Icons.credit_card,
                            keyboardType: TextInputType.number,
                            maxLength: 12,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your Aadhaar number';
                              }
                              if (value.length != 12) {
                                return 'Aadhaar number must be 12 digits';
                              }
                              return null;
                            },
                            saffron: saffron,
                            green: green,
                          ),

                          const SizedBox(height: 32),

                          // Signup Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: isLoading ? null : handleSignup,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: saffron,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 8,
                                shadowColor: saffron.withOpacity(0.6),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                                  : const Text(
                                'Create Account',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: white,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Animated messages (error or success)
                          FadeTransition(
                            opacity: _messageFadeAnimation,
                            child: SlideTransition(
                              position: _messageSlideAnimation,
                              child: _buildMessageWidget(saffron, green),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Info box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Your data is securely stored on your device. This demo creates accounts instantly.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: green.withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    required Color saffron,
    required Color green,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: saffron),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[100],
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: saffron, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: green.withOpacity(0.4), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade700, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.red.shade700, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      cursorColor: saffron,
      style: TextStyle(color: Color(0xFF138808)),
    );
  }

  Widget _buildMessageWidget(Color saffron, Color green) {
    if (errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          border: Border.all(color: Colors.red[300]!),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMessage!,
                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    } else if (isSignupComplete) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          border: Border.all(color: Colors.green[300]!),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Account Created Successfully!',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome to Tourist Safety App!',
              style: TextStyle(
                color: Colors.green[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}