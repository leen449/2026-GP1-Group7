import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../submit_case/submit_case_screen.dart';
import '../ocr/scan_screen.dart';
import '../auth/auth_screen.dart';
import 'modify_screen.dart';
import 'dart:ui';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const Color _pageBg = Colors.white;
  static const Color _cardGrey = Color(0xFFF2F3F5);
  static const Color _textDark = Color(0xFF1E1E1E);
  static const Color _textMuted = Color(0xFF6B6B6B);
  static const Color _bannerBlue = Color(0xFF6F8FA7);

  // ── بيانات المستخدم ──
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      setState(() => _userName = doc.data()?['name'] ?? '');
    }
  }

  // ── Logout ──
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42, height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 10),
                ListTile(
                  title: const Text('Scan Registration', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
                  },
                ),
                ListTile(
                  title: const Text('Add Manually', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to Add Manually screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add Manually')),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProfileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42, height: 4,
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Modify personal information', style: TextStyle(fontWeight: FontWeight.w600)),
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
                  title: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _logout();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text('History', style: TextStyle(color: _textDark, fontWeight: FontWeight.w700)),
          iconTheme: const IconThemeData(color: _textDark),
        ),
        body: const Center(child: Text('History Page')),
      )),
    );
  }

 void _onNavTap(int index) {
  // add later the other pages navigation logic here
  if (index == _currentIndex) return;

  if (index == 1) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubmitCaseScreen()),
    ).then((_) => setState(() => _currentIndex = 0));
    return;
  }

  setState(() => _currentIndex = index);

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text("Tab ${index + 1} coming soon")));
}

  @override
  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: _pageBg,
    body: Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topGreeting(),
                  const SizedBox(height: 12),
                  const Text(
                    'Manage Your Vehicles And Reports Easily !',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textDark),
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
        ),
        _bottomNav(),
      ],
    ),
  );
}

  // ── Top Greeting ──
  Widget _topGreeting() {
    return Row(
      children: [
        GestureDetector(
          onTap: _showProfileOptions,
          child: ClipOval(
            child: Image.asset('assets/icons/profile.png', width: 34, height: 34, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Hello $_userName!',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textDark),
        ),
      ],
    );
  }

  // ── Banner ──
  Widget _bannerCard() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 12, right: 12, top: 12, bottom: 22,
            child: Container(
              decoration: BoxDecoration(color: _bannerBlue, borderRadius: BorderRadius.circular(22)),
            ),
          ),
          Positioned(
            left: 40, top: 20,
            child: Image.asset('assets/images/orange_car.png', width: 300, fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  // ── My Vehicles Header ──
  Widget _myVehiclesHeader() {
    return Row(
      children: [
        const Text('My Vehicles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textDark)),
        const Spacer(),
        GestureDetector(
          onTap: _showAddOptions,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: _cardGrey, shape: BoxShape.circle),
            child: const Icon(Icons.add, size: 20, color: _textDark),
          ),
        ),
      ],
    );
  }

  // ── Vehicles List من Firestore ──
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
          return const SizedBox(height: 112, child: Center(child: CircularProgressIndicator()));
        }

        final vehicles = snapshot.data?.docs ?? [];

        if (vehicles.isEmpty) {
          return Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _cardGrey, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              'No vehicles registered yet.',
              style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          );
        }

        return SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final v = vehicles[i].data() as Map<String, dynamic>;
              final name = '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim();
              final plate = v['plateNumber'] ?? '';

              return Container(
                width: 145,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(color: _cardGrey, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Image.asset('assets/images/car2.png', width: 76, fit: BoxFit.contain),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plate,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Recent Report Header ──
  Widget _reportHistoryHeader() {
    return Row(
      children: [
        const Text('Recent Report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _textDark)),
        const Spacer(),
        GestureDetector(
          onTap: _openHistory,
          child: const Icon(Icons.chevron_right, size: 28, color: _textMuted),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    final bool approved = status.toLowerCase() == 'approved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: approved ? const Color(0xFFDFF3E3) : const Color(0xFFF6E3D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: approved ? const Color(0xFF2E7D32) : const Color(0xFFB35A2A),
        ),
      ),
    );
  }

  // ── Report List من Firestore ──
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
            decoration: BoxDecoration(color: _cardGrey, borderRadius: BorderRadius.circular(18)),
            child: const Center(
              child: Text(
                'No reports yet.',
                style: TextStyle(color: _textMuted, fontSize: 14, fontWeight: FontWeight.w500),
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

            // جلب اسم السيارة من vehicleId
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
                  carName = '${vData['make'] ?? ''} ${vData['model'] ?? ''}'.trim();
                  plate = vData['plateNumber'] ?? '';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _openHistory,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: _cardGrey, borderRadius: BorderRadius.circular(18)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(carName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
                                const SizedBox(height: 4),
                                Text(plate, style: const TextStyle(fontSize: 12, color: _textMuted, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Text(dateStr, style: const TextStyle(fontSize: 12, color: _textDark, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          _statusBadge(status),
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

  // ── Bottom Nav (نفس الكود الأصلي بدون تغيير) ──
  Widget _bottomNav() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.35),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withOpacity(0.50), width: 1.2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(index: 0, label: 'home', icon: Icons.home_rounded),
                  _navItem(index: 1, label: 'accident', icon: Icons.directions_car),
                  _navItem(index: 2, label: 'history', icon: Icons.description_outlined),
                  _navItem(index: 3, label: 'claim', icon: Icons.assignment_outlined),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem({required int index, required String label, required IconData icon}) {
    final bool active = _currentIndex == index;
    const Color activeBlue = Color(0xFF2A5BD7);
    const Color inactiveGrey = Color(0xFF8A8A8A);

    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 74, height: 50,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(index == _currentIndex),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                final shake = active ? (value < 0.5 ? value * 2 * 6 : (1 - value) * 2 * 6) : 0.0;
                return Transform.translate(
                  offset: Offset(shake * (value < 0.25 || value > 0.75 ? -1 : 1), 0),
                  child: Icon(icon, size: 22, color: active ? activeBlue : inactiveGrey),
                );
              },
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? activeBlue : inactiveGrey),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}