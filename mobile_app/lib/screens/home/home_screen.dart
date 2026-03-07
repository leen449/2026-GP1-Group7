import 'package:flutter/material.dart';
import '../submit_case/submit_case_screen.dart';
import '../ocr/scan_screen.dart';
//import '';
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
  static const Color _navPill = Color(0xFFEFEFF2);
  static const Color _navActiveCircle = Color(0xFFDDE8FF);
  static const Color _navActiveIcon = Color(0xFF2F5D8C);
  static const Color _navInactiveIcon = Color(0xFF8E8E8E);

  static const Color _bannerBlue = Color(0xFF6F8FA7);

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
                    'Modify personal information',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Modify personal information (Placeholder)',
                        ),
                      ),
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

  Widget _historyPlaceholder() {
    return Scaffold(
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
      body: const Center(
        child: Text(
          'History Page (Placeholder)',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _historyPlaceholder()),
    );
  }

  void _onNavTap(int index) {
    if (index == 0) {
      setState(() => _currentIndex = 0);
      return;
    }

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubmitCaseScreen()),
      ).then((_) {
        // ✅ Reset back to home tab when returning from SubmitCaseScreen
        setState(() => _currentIndex = 0);
      });
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Tab ${index + 1} (Placeholder)')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
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
          Positioned(bottom: 0, left: 0, right: 0, child: _bottomNav()),
        ],
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
        const Text(
          'Hello Sarah!',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  Widget _bannerCard() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        // color: _cardGrey,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            bottom: 22,
            child: Container(
              decoration: BoxDecoration(
                color: _bannerBlue,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),

          Positioned(
            left: 40,
            top: 20,
            child: Image.asset(
              'assets/images/orange_car.png',
              width: 300,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
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
    final vehicles = [
      {'name': 'Honda Accord', 'plate': 'A S T R 3456'},
      {'name': 'Toyota Camry', 'plate': 'A D W R 5463'},
      {'name': 'Toyota Accent', 'plate': 'A C V B 9876'},
      {'name': 'Hyundai Elantra', 'plate': 'B T R S 2211'},
      {'name': 'Kia K5', 'plate': 'K S A 7788'},
    ];

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final v = vehicles[i];
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.white,
                    appBar: AppBar(
                      backgroundColor: Colors.white,
                      elevation: 0,
                      iconTheme: const IconThemeData(color: _textDark),
                      title: Text(
                        v['name']!,
                        style: const TextStyle(
                          color: _textDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    body: Center(
                      child: Text('View Vehicle (Placeholder)\n${v['plate']}'),
                    ),
                  ),
                ),
              );
            },
            child: Container(
              width: 145,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: _cardGrey,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/car2.png',
                    width: 76,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    v['name']!,
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
                    v['plate']!,
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
  }

  Widget _reportHistoryHeader() {
    return Row(
      children: [
        const Text(
          'Report History',
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
    final bool approved = status == 'Approved';
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

  Widget _reportList() {
    final reports = [
      {
        'car': 'Honda Accord',
        'plate': 'S A R 3456',
        'date': '12/4/2026',
        'status': 'In Progress',
      },
      {
        'car': 'Honda Accord',
        'plate': 'S A R 3456',
        'date': '12/4/2026',
        'status': 'Approved',
      },
      {
        'car': 'Honda Accord',
        'plate': 'S A R 3456',
        'date': '12/4/2026',
        'status': 'In Progress',
      },
    ];

    return Column(
      children: reports.map((r) {
        final status = r['status'] as String;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _openHistory,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                          r['car'] as String,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r['plate'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r['date'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _statusBadge(status),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

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
                border: Border.all(
                  color: Colors.white.withOpacity(0.50),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(index: 0, label: 'home', icon: Icons.home_rounded),
                  _navItem(
                    index: 1,
                    label: 'accident',
                    icon: Icons.directions_car,
                  ),
                  _navItem(
                    index: 2,
                    label: 'history',
                    icon: Icons.description_outlined,
                  ),
                  _navItem(
                    index: 3,
                    label: 'claim',
                    icon: Icons.assignment_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool active = _currentIndex == index;
    const Color activeBlue = Color(0xFF2A5BD7);
    const Color inactiveGrey = Color(0xFF8A8A8A);

    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 74,
        height: 50,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
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
                final shake = active
                    ? (value < 0.5 ? value * 2 * 6 : (1 - value) * 2 * 6)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(
                    shake * (value < 0.25 || value > 0.75 ? -1 : 1),
                    0,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: active ? activeBlue : inactiveGrey,
                  ),
                );
              },
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? activeBlue : inactiveGrey,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
