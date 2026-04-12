import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../ocr/scan_screen.dart';
import '../auth/auth_screen.dart';
import 'modify_screen.dart';
import 'dart:ui';
import '../NavBar/nav_bar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../vehicle/add_vehicle_screen.dart';
import '../vehicle/vehicle_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _pageBg = Colors.white;
  static const Color _cardGrey = Color(0xFFF2F3F5);
  static const Color _textDark = Color(0xFF1E1E1E);
  static const Color _textMuted = Color(0xFF6B6B6B);
  static const Color _bannerBlue = Color(0xFF6F8FA7);

  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('userID', isEqualTo: uid)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty && mounted) {
      setState(() => _userName = query.docs.first.data()['name'] ?? '');
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
                title: const Text(
                  'Scan Registration',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  );
                },
              ),
              ListTile(
                title: const Text(
                  'Add Manually',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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
                  'Modify personal information',
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
                  'Log out',
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
              'History',
              style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
            ),
            iconTheme: const IconThemeData(color: _textDark),
          ),
          body: const Center(child: Text('History Page')),
        ),
      ),
    );
  }

  //  New method to show OCR failure dialog
  void _showOcrFailedDialog() {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Constrain the dialog width for larger screens (Tablets/Desktop)
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
          ),
          child: SingleChildScrollView(
            // Prevents overflow on small screens
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.06), // Dynamic padding
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: screenWidth * 0.08, // Dynamic icon size
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        // Prevents text overflow in the Row
                        child: Text(
                          'Verification Failed',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045, // Dynamic font
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.04),
                  Text(
                    'We could not verify the uploaded PDF as a valid Najm accident report.\n\nPlease submit a new case and make sure you upload the correct Najm accident report file.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035, // Dynamic font
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
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: screenWidth * 0.03,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: Text(
                        'Got it',
                        style: TextStyle(fontSize: screenWidth * 0.04),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
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
              const SizedBox(height: 12),
              const Text(
                'Manage Your Vehicles And Reports Easily !',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 14),
              _bannerCard(),
              const SizedBox(height: 18),
              _myVehiclesHeader(),
              const SizedBox(height: 10),
              _vehiclesHorizontalList(),
              const SizedBox(height: 18),
              _reportHistoryHeader(),
              const SizedBox(height: 10),
              _reportList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topGreeting() {
    return Row(
      children: [
        GestureDetector(
          onTap: _showProfileOptions,
          child: ClipOval(
            child: Image.asset(
              'assets/icons/profile.png',
              width: 34,
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Hello $_userName!',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  Widget _bannerCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cardHeight = w * 0.50;

        // ✅ Stack with Clip.none so car overflows outside the blue box
        // matching the original Figma design
        return SizedBox(
          height: cardHeight + 30, // extra space for car overflow at bottom
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Blue background card
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 30, // card stops 30px before bottom
                child: Container(
                  decoration: BoxDecoration(
                    color: _bannerBlue,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),

              // Car image — positioned to overflow bottom of card
              Positioned(
                left: w * 0.04,
                right: 0,
                top: w * 0.02,
                bottom: 0, // extends 30px below the card
                child: Image.asset(
                  'assets/images/orange_car.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _myVehiclesHeader() {
    return Row(
      children: [
        const Text(
          'My Vehicles',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _textDark,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _showAddOptions,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: _cardGrey, shape: BoxShape.circle),
            child: const Icon(Icons.add, size: 20, color: _textDark),
          ),
        ),
      ],
    );
  }

  Widget _vehiclesHorizontalList() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vehicles')
          .where('ownerId', isEqualTo: uid)
          .where('isArchived', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final vehicles = snapshot.data?.docs ?? [];

        if (vehicles.isEmpty) {
          return Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _cardGrey,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No vehicles registered yet.',
              style: TextStyle(
                color: _textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }

        // ✅ Use LayoutBuilder so card height scales with screen width
        return LayoutBuilder(
          builder: (context, constraints) {
            // Card is 145px wide — height proportional to avoid overflow
            // image(76) + padding(20) + text(12) + spacing(8) + plate(11+2) = ~130
            const cardHeight = 130.0;

            return SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: vehicles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final v = vehicles[i].data() as Map<String, dynamic>;
                  final name = '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim();
                  final plate = v['plateNumber'] ?? '';

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VehicleDetailsScreen(
                            vehicleId: vehicles[i].id,
                            vehicleData: v,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 145,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _cardGrey,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/car2.png',
                            width: 76,
                            height: 52,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            plate,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _reportHistoryHeader() {
    return Row(
      children: [
        const Text(
          'Recent Report',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _textDark,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _openHistory,
          child: const Icon(Icons.chevron_right, size: 28, color: _textMuted),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final s = status.toLowerCase().trim();
    final displayStatus = s == 'ocr_failed' ? 'Verification Failed' : status;

    Color bgColor;
    Color textColor;

    if (s == 'approved') {
      bgColor = const Color(0xFFDFF3E3);
      textColor = const Color(0xFF2E7D32);
    } else if (s == 'pending') {
      bgColor = const Color(0xFFE8EDF3);
      textColor = const Color(0xFF4A6072);
    } else if (s == 'ocr_failed') {
      bgColor = const Color(0xFFFFE7E7);
      textColor = const Color(0xFFC62828);
    } else {
      bgColor = const Color(0xFFF6E3D8);
      textColor = const Color(0xFFB35A2A);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        displayStatus,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: textColor,
        ),
      ),
    );
  }

  Widget _reportList() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .where('ownerId', isEqualTo: uid)
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
              color: _cardGrey,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text(
                'No reports yet.',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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
            final dateStr = date != null
                ? '${date.day}/${date.month}/${date.year}'
                : '';

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
                  carName = '${vData['make'] ?? ''} ${vData['model'] ?? ''}'
                      .trim();
                  plate = vData['plateNumber'] ?? '';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openHistory,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _cardGrey,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  carName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  plate,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _statusBadge(status),
                              if (status.toLowerCase() == 'ocr_failed') ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _showOcrFailedDialog,
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 22,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
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
