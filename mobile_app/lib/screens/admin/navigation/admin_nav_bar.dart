import 'dart:ui';

import 'package:flutter/material.dart';

import '../home/admin_home_screen.dart';

class AdminBottomNav extends StatefulWidget {
  const AdminBottomNav({super.key});

  @override
  State<AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends State<AdminBottomNav> {
  int _currentIndex = 0;

  static const Color _activeBlue = Color(0xFF2A5BD7);
  static const Color _inactiveGrey = Color(0xFF8A8A8A);

  static const List<_AdminNavItemData> _items = [
    _AdminNavItemData(label: 'الرئيسية', icon: Icons.home_rounded),
    _AdminNavItemData(label: 'الحالات', icon: Icons.description_outlined),
    _AdminNavItemData(label: 'الاعتراضات', icon: Icons.assignment_outlined),
  ];

  void _onTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const AdminHomeScreen(),
      const _AdminPlaceholderPage(title: 'الحالات'),
      const _AdminPlaceholderPage(title: 'الاعتراضات'),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: pages),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildNavBar()),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    final sw = MediaQuery.of(context).size.width;
    final itemWidth = ((sw - 44 - 32) / 3).clamp(68.0, 98.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.08,
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
                textDirection: TextDirection.rtl,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _items.length,
                  (i) => _AdminNavItem(
                    data: _items[i],
                    active: _currentIndex == i,
                    width: itemWidth,
                    onTap: () => _onTap(i),
                    activeColor: _activeBlue,
                    inactiveColor: _inactiveGrey,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminPlaceholderPage extends StatelessWidget {
  const _AdminPlaceholderPage({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      body: SafeArea(
        child: Center(
          child: Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: Color(0xFF071A3D),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminNavItemData {
  final String label;
  final IconData icon;

  const _AdminNavItemData({required this.label, required this.icon});
}

class _AdminNavItem extends StatelessWidget {
  const _AdminNavItem({
    required this.data,
    required this.active,
    required this.width,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  final _AdminNavItemData data;
  final bool active;
  final double width;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: width,
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
              key: ValueKey(active),
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
                    data.icon,
                    size: 22,
                    color: active ? activeColor : inactiveColor,
                  ),
                );
              },
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: width < 78 ? 10 : 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? activeColor : inactiveColor,
              ),
              child: Text(data.label),
            ),
          ],
        ),
      ),
    );
  }
}
