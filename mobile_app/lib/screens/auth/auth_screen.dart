import 'package:flutter/material.dart';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'package:cloud_firestore/cloud_firestore.dart';


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {


  bool isLogin = true; // true = Login , false = Sign up

  // Controllers (Login)
  final TextEditingController _loginPhoneController = TextEditingController();

  // Controllers (Sign up)
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _signupPhoneController = TextEditingController();

Future<void> _testBackendConnection() async {
  try {
    final response = await http.get(
      Uri.parse('http://10.0.2.2:8000/'),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Backend response: ${response.body}'),
      ),
    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connection failed: $e'),
      ),
    );
  }
}



  @override
  void dispose() {
    _loginPhoneController.dispose();
    _nameController.dispose();
    _nationalIdController.dispose();
    _signupPhoneController.dispose();
    super.dispose();
  }

  TextStyle _textStyle({double fontSize = 14, Color color = Colors.black}) {
    return TextStyle(fontSize: fontSize, color: color);
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: _textStyle(fontSize: 14, color: Colors.black87)),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _primaryButton({required String text, required VoidCallback onTap}) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0B3B66),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(text, style: _textStyle(fontSize: 16, color: Colors.white)),
      ),
    );
  }

  Widget _toggleBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => isLogin = false), // Sign up
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.transparent : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Sign up',
                  style: _textStyle(
                    fontSize: 14,
                    color: isLogin ? Colors.black54 : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => isLogin = true), // Log in
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Log in',
                  style: _textStyle(
                    fontSize: 14,
                    color: isLogin ? Colors.black87 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Phone Number'),
        _inputField(
          controller: _loginPhoneController,
          hint: 'Your Phone Number',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 90),
        _primaryButton(
          text: 'Log in',
          onTap: () {
            Navigator.pushNamed(context, '/verification');
          },
        ),
      ],
    );
  }

  Widget _signupContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Name'),
        _inputField(controller: _nameController, hint: 'Name'),
        const SizedBox(height: 14),
        _label('National / Residence ID'),
        _inputField(
          controller: _nationalIdController,
          hint: 'ID',
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        _label('Phone Number'),
        _inputField(
          controller: _signupPhoneController,
          hint: 'Your Phone Number',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 40),
        _primaryButton(
          text: 'Sign in',
          onTap: () {
            Navigator.pushNamed(context, '/verification');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    




    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            children: [
              const SizedBox(height: 18),

              SizedBox(
                height: 140,
                child: Center(
                  child: isLogin
                      ? Text(
                          'Welcome Back',
                          style: _textStyle(fontSize: 34, color: Colors.black),
                        )
                      : Image.asset(
                          'assets/icons/logo.png',
                          height: 120,
                          fit: BoxFit.contain,
                        ),
                ),
              ),

              const SizedBox(height: 18),
              _toggleBar(),
              const SizedBox(height: 50),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLogin ? _loginContent() : _signupContent(),
              ),
              const SizedBox(height: 20),
              _primaryButton(
  text: 'Test Backend',
  onTap: () async {
  await FirebaseFirestore.instance.collection('test').add({
    'created_at': FieldValue.serverTimestamp(),
    'status': 'connected',
  });

  print("Document added");
}
),
            ],
            
          ),
        ),
      ),
    );
  }
}
