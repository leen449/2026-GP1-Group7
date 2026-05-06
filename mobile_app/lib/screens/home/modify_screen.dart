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
  // ── Colors — consistent with the rest of the app ──────────────────
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _navy = Color(0xFF0B4A7D);
  static const Color _borderColor = Color(0xFFE8EEF7);

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
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: const SizedBox(),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: _textDark),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text(
          'المعلومات الشخصية',
          style: TextStyle(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Profile avatar + name ──────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEAF2FF),
                        border: Border.all(color: _borderColor, width: 2),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/profile.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _name,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Info card ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
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
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _pageBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _borderColor),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '+966 $_phone',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 14,
                              color: _textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: _navy,
                          ),
                        ],
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
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: _primaryBlue,
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
    );
  }

  // ── Field label — RTL aligned ──────────────────────────────────────
  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _textDark,
        ),
      ),
    );
  }

  // ── Read-only field — matches app's bordered card style ───────────
  Widget _readOnlyField(String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _pageBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _textDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.lock_outline, size: 16, color: _navy),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'لا يمكن التعديل',
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontSize: 11, color: _textMuted),
        ),
      ],
    );
  }
}
