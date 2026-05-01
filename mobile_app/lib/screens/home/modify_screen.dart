import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/change_phone_screen.dart';

class ModifyScreen extends StatefulWidget {
  const ModifyScreen({super.key});

  @override
  State<ModifyScreen> createState() => _ModifyScreenState();
}

class _ModifyScreenState extends State<ModifyScreen> {
  static const Color _pageBg = Color(0xFFF6F6F6);
  static const Color _textDark = Color(0xFF1E1E1E);
  static const Color _cardGrey = Color(0xFFFFFFFF);

  String _name = '';
  String _nationalId = '';
  String _phone = '';
  String _dateOfBirth = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final phone = user.phoneNumber;
    if (phone == null) return;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();

    if (query.docs.isEmpty || !mounted) return;

    final data = query.docs.first.data();
    setState(() {
      _name = data['name'] ?? '';
      _nationalId = data['nationalID'] ?? '';
      _phone = (data['phoneNumber'] ?? '').replaceFirst('+966', '');
      _dateOfBirth = data['dateOfBirth'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(247, 250, 255, 1),
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 247, 250, 255),
          elevation: 0,
          automaticallyImplyLeading: false,

          actions: [
            Transform.rotate(
              angle: 3.1416, // يقلب السهم 180 درجة
              child: const BackButton(color: _textDark),
            ),
          ],
          title: const Text(
            'المعلومات الشخصية',
            style: TextStyle(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // صورة البروفايل
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/icons/profile.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardGrey,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // الاسم
                      _fieldLabel('الاسم الكامل'),
                      _readOnlyField(_name),
                      const SizedBox(height: 18),

                      // الهوية
                      _fieldLabel('رقم الهوية / الإقامة'),
                      _readOnlyField(_nationalId),
                      const SizedBox(height: 18),

                      // تاريخ الميلاد
                      _fieldLabel('تاريخ الميلاد'),
                      _readOnlyField(_dateOfBirth),
                      const SizedBox(height: 18),

                      // رقم الجوال
                      _fieldLabel('رقم الجوال'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '+966 $_phone',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1E1E1E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ChangePhoneScreen(returnToHome: true),
                            ),
                          ).then((_) => _loadUserData());
                        },
                        child: const Text(
                          'تغيير رقم الجوال',
                          style: TextStyle(
                            color: Color(0xFF0B3B66),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
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
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
    );
  }

  Widget _readOnlyField(String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.lock_outline, size: 16, color: Color(0xFF0B4A7D)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "لا يمكن التعديل",
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
        ),
      ],
    );
  }
}
