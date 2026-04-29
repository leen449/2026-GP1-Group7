import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';

import '../ocr/scan_screen.dart';
import 'modify_screen.dart';

import '../vehicle/add_vehicle_screen.dart';
import '../vehicle/vehicle_details_screen.dart';
import '../vehicle/all_vehicles_screen.dart';
import '../submit_case/Case_Details_Screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _navy = Color(0xFF061943);

  String _userName = '';
  String _userDocId = '';
Widget _centerInfoBox(String title, String value, {bool ltr = false}) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAFF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8EEF7)),
    ),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            color: Color(0xFF8B97AA),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Directionality(
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            child: Text(
              value.toString().trim().isEmpty ? '—' : value.toString(),
              textAlign: ltr ? TextAlign.left : TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF071A3D),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final phone = user.phoneNumber;
    if (phone == null) return;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty && mounted) {
      setState(() {
        _userName = query.docs.first.data()['name'] ?? '';
        _userDocId = query.docs.first.id;
      });
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _addOptionCard(
                      title: 'إضافة يدوية',
                      subtitle: 'أدخل بيانات المركبة\nيدويًا خطوة بخطوة',
                      icon: Icons.edit_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddVehicleScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _addOptionCard(
                      title: 'مسح الاستمارة',
                      subtitle: 'امسح استمارة المركبة\nواستخرج البيانات تلقائيًا',
                      icon: Icons.document_scanner_outlined,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ScanScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: _primaryBlue, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textMuted,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text(
                  'تعديل المعلومات الشخصية',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ModifyScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'تسجيل الخروج',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'السجل',
              style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
            ),
            iconTheme: const IconThemeData(color: _textDark),
          ),
          body: const Center(child: Text('History Page')),
        ),
      ),
    );
  }

  void _showOcrFailedDialog() {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.06),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: screenWidth * 0.12,
                ),
                SizedBox(height: screenWidth * 0.04),
                Text(
                  'فشل التحقق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: screenWidth * 0.045,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                SizedBox(height: screenWidth * 0.04),
                Text(
                  'لم نتمكن من التحقق من الملف المرفوع كتقرير نجم صحيح.\n\nيرجى إرسال بلاغ جديد والتأكد من رفع تقرير نجم الصحيح.',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: screenWidth * 0.035,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: screenWidth * 0.06),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: screenWidth * 0.03,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'حسنًا',
                      style: TextStyle(fontSize: screenWidth * 0.04),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topGreeting(),
              const SizedBox(height: 18),
              _bannerCard(),
              const SizedBox(height: 20),
              _myVehiclesHeader(),
              const SizedBox(height: 12),
              _vehiclesHorizontalList(),
              const SizedBox(height: 22),
              _reportHistoryHeader(),
              const SizedBox(height: 12),
              _reportList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topGreeting() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: [
            GestureDetector(
              onTap: _showProfileOptions,
              child: ClipOval(
                child: Image.asset(
                  'assets/icons/profile.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'مرحباً، $_userName!',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'نسعد بخدمتك',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: _textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _bannerCard() {
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(26),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Image.asset(
          'assets/images/home_image.png',
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _myVehiclesHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: _showAddOptions,
          child: Row(
  mainAxisSize: MainAxisSize.min,
  children: const [
    Text(
      'إضافة مركبة',
      textDirection: TextDirection.rtl,
      style: TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    SizedBox(width: 10),
    Icon(
      Icons.add,
      color: Color(0xFF2563EB),
      size: 28,
    ),
  ],
),
        ),
        const Spacer(),
        const Text(
          'مركباتي',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: _textDark,
          ),
        ),
      ],
    );
  }
  void _showVehicleCard(BuildContext context, String id, Map<String, dynamic> v) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'vehicle_details',
    barrierColor: Colors.black.withOpacity(0.28),
    pageBuilder: (_, __, ___) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Center(
  child: Text(
    'تفاصيل المركبة',
    textDirection: TextDirection.rtl,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      color: Color(0xFF071A3D),
    ),
  ),
),
const SizedBox(height: 12),
                  Center(
  child: Container(
    width: 70,
    height: 70,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Icon(
      Icons.directions_car_rounded,
      color: Color(0xFF2563EB),
      size: 36,
    ),
  ),
),
const SizedBox(height: 14),
                  Text(
                    '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim(),
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF071A3D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _centerInfoBox('الشركة', v['make'] ?? ''),
_centerInfoBox('الطراز', v['model'] ?? ''),
_centerInfoBox('السنة', v['year'] ?? ''),
_centerInfoBox('اللون', v['color'] ?? ''),
_centerInfoBox('اللوحة', v['arabicPlateNumber'] ?? v['plateNumber'] ?? ''),
_centerInfoBox('رقم الهيكل', v['chassisNumber'] ?? '', ltr: true),
const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('تأكيد الحذف', textDirection: TextDirection.rtl),
                            content: const Text('هل تريد حذف المركبة؟', textDirection: TextDirection.rtl),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('إلغاء'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('حذف', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await FirebaseFirestore.instance
                              .collection('vehicles')
                              .doc(id)
                              .update({
                            'isArchived': true,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم حذف المركبة')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('حذف المركبة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}


  Widget _vehiclesHorizontalList() {
  if (_userDocId.isEmpty) return const SizedBox();

  final screenWidth = MediaQuery.of(context).size.width;

  // Responsive card size
  final cardWidth = (screenWidth * 0.30).clamp(110.0, 140.0);
  final listHeight = (screenWidth * 0.44).clamp(165.0, 195.0);

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('vehicles')
        .where('ownerId', isEqualTo: _userDocId)
        .where('isArchived', isEqualTo: false)
        .limit(3)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return SizedBox(
          height: listHeight,
          child: const Center(child: CircularProgressIndicator()),
        );
      }

      final vehicles = snapshot.data?.docs ?? [];

      return SizedBox(
        height: listHeight,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse:false,
            itemCount: vehicles.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == vehicles.length) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllVehiclesScreen(ownerId: _userDocId),
                      ),
                    );
                  },
                  child: _vehicleCardBase(
                    width: cardWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        Icon(
                          Icons.grid_view_rounded,
                          size: 32,
                          color: Color(0xFF2563EB),
                        ),
                        Text(
                          'عرض كل\nالمركبات',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                            height: 1.25,
                          ),
                        ),
                    
                      ],
                    ),
                  ),
                );
              }

              final doc = vehicles[i];
              final v = doc.data() as Map<String, dynamic>;
              final name = '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim();
              final plate = v['plateNumber'] ?? '';

              return GestureDetector(
                onTap: () {
                  _showVehicleCard(context, doc.id, v);
                },
                child: _vehicleCardBase(
                  width: cardWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Image.asset(
                        'assets/images/allcar_card.PNG',
                        width: cardWidth * 0.60,
                        height: listHeight * 0.45,
                        fit: BoxFit.contain,
                      ),

                      Flexible(
                        child: Text(
                          name.isEmpty ? 'مركبة' : name,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                            height: 1.2,
                          ),
                        ),
                      ),

                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          plate,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: _textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFEAF2FF),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF2563EB),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
Widget _vehicleCardBase({
  required double width,
  required Widget child,
}) {
  return Container(
    width: width,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}
  Widget _reportHistoryHeader() {
  return Row(
    children: [
      GestureDetector(
        onTap: _openHistory,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: const [
            Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: _primaryBlue,
            ),
            SizedBox(width: 8),
            Text(
              'عرض الكل',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: _primaryBlue,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const Spacer(),
      const Text(
        'التقارير الأخيرة',
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: _textDark,
        ),
      ),
    ],
  );
}

  Widget _statusBadge(String status) {
    final s = status.toLowerCase().trim();

    String displayStatus;
    Color bgColor;
    Color textColor;
    IconData icon;

    if (s == 'approved' || s == 'completed') {
      displayStatus = 'مكتمل';
      bgColor = const Color(0xFFE7F8EF);
      textColor = const Color(0xFF159B55);
      icon = Icons.check_circle_outline_rounded;
    } else if (s == 'pending') {
      displayStatus = 'قيد المراجعة';
      bgColor = const Color(0xFFEAF1FF);
      textColor = const Color(0xFF2E63D9);
      icon = Icons.hourglass_empty_rounded;
    } else if (s == 'ocr_failed') {
      displayStatus = 'فشل الفحص';
      bgColor = const Color(0xFFFFEEF0);
      textColor = const Color(0xFFE33B4E);
      icon = Icons.warning_amber_rounded;
    } else {
      displayStatus = 'قيد التحليل';
      bgColor = const Color(0xFFFFF1E6);
      textColor = const Color(0xFFE27A2E);
      icon = Icons.access_time_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 5),
          Text(
            displayStatus,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportIcon(String status) {
    final s = status.toLowerCase().trim();

    Color bgColor;
    Color iconColor;
    IconData icon;

    if (s == 'approved' || s == 'completed') {
      bgColor = const Color(0xFFE7F8EF);
      iconColor = const Color(0xFF159B55);
      icon = Icons.verified_user_outlined;
    } else if (s == 'pending') {
      bgColor = const Color(0xFFEAF1FF);
      iconColor = const Color(0xFF2E63D9);
      icon = Icons.search_rounded;
    } else if (s == 'ocr_failed') {
      bgColor = const Color(0xFFFFEEF0);
      iconColor = const Color(0xFFE33B4E);
      icon = Icons.gpp_bad_outlined;
    } else {
      bgColor = const Color(0xFFFFF1E6);
      iconColor = const Color(0xFFE27A2E);
      icon = Icons.description_outlined;
    }

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 25),
    );
  }

  Widget _reportList() {
    if (_userDocId.isEmpty) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .where('ownerId', isEqualTo: _userDocId)
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reports = snapshot.data?.docs ?? [];

        if (reports.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE8EEF7)),
            ),
            child: const Center(
              child: Text(
                'لا توجد تقارير حتى الآن',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        return Column(
          children: reports.map((doc) {
            final r = doc.data() as Map<String, dynamic>;
            final status = r['status'] ?? '';
            final date = r['createdAt'] != null
                ? (r['createdAt'] as Timestamp).toDate()
                : null;
            final dateStr =
                date != null ? '${date.day}/${date.month}/${date.year}' : '';

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('vehicles')
                  .doc(r['vehicleId'])
                  .get(),
              builder: (context, vSnap) {
                String carName = '';
                String plate = '';

                if (vSnap.hasData && vSnap.data!.exists) {
                  final vData = vSnap.data!.data() as Map<String, dynamic>;
                  carName =
                      '${vData['make'] ?? ''} ${vData['model'] ?? ''}'.trim();
                  plate = vData['plateNumber'] ?? '';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CaseDetailsScreen(caseId: doc.id),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE8EEF7)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.035),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child:Directionality(
  textDirection: TextDirection.ltr,
  child: Row(
    children: [
      // Back arrow (fixed to the far left)
      const Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 17,
        color: _textDark,
      ),

      const SizedBox(width: 10),

      // Status badge (placed after the arrow)
      GestureDetector(
        onTap: status.toLowerCase() == 'ocr_failed'
            ? _showOcrFailedDialog
            : null,
        child: _statusBadge(status),
      ),

      const SizedBox(width: 10),

      // Main content (car name, plate, date)
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Car name (RTL)
            Text(
              carName,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),

            const SizedBox(height: 3),

            // Plate number (LTR for correct formatting)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                plate,
                style: const TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 3),

            // Report date
            Text(
              dateStr,
              style: const TextStyle(
                fontSize: 12,
                color: _textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),

      const SizedBox(width: 10),

      // Status icon (circle on the right)
      _reportIcon(status),
    ],
  ),
)
                    ),
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }
}
