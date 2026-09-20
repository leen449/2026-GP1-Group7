import 'dart:ui';

import 'package:flutter/material.dart';

import '../view_cases/admin_cases_screen.dart';
import '../home/admin_home_screen.dart';
import '../view_objections/admin_objections_screen.dart';

class AdminBottomNav extends StatefulWidget {
  const AdminBottomNav({super.key});

  @override
  State<AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends State<AdminBottomNav> {
  int _currentIndex = 0;

  // Existing colors from the current admin navigation.
  static const Color _activeBlue = Color(0xFF2A5BD7);
  static const Color _inactiveGrey = Color(0xFF8A8A8A);

  static const List<_AdminNavItemData> _items = [
    _AdminNavItemData(
      label: 'لوحة التحكم',
      icon: Icons.grid_view_rounded,
    ),
    _AdminNavItemData(
      label: 'الحالات',
      icon: Icons.directions_car_rounded,
    ),
    _AdminNavItemData(
      label: 'الاعتراضات',
      icon: Icons.chat_bubble_outline_rounded,
    ),
  ];

  void _onTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      AdminHomeScreen(),
      AdminCasesScreen(),
      AdminObjectionsScreen(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: pages),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    final size = MediaQuery.sizeOf(context);
    final sw = size.width;
    final sh = size.height;

    final horizontalPad = (sw * 0.052).clamp(14.0, 24.0);
    final barHeight = (sh * 0.08).clamp(62.0, 78.0);
    final available = sw - (horizontalPad * 2) - 26;
    final itemWidth = (available / 3).clamp(72.0, 110.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPad,
          6,
          horizontalPad,
          12,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: barHeight,
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

class _AdminNavItemData {
  final String label;
  final IconData icon;

  const _AdminNavItemData({
    required this.label,
    required this.icon,
  });
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
    final sw = MediaQuery.sizeOf(context).width;
    final scale = (sw / 430.0).clamp(0.82, 1.08);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: width,
        height: 50 * scale,
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
                    size: 22 * scale,
                    color: active ? activeColor : inactiveColor,
                  ),
                );
              },
            ),
            SizedBox(height: 3 * scale),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                data.label,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 10.5 * scale,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? activeColor : inactiveColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
