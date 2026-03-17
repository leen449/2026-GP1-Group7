import 'package:flutter/material.dart';
import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────
// Shared navigation bar widget used by HomeScreen and SubmitCaseScreen
// Ensures identical appearance and animation across all screens
// ─────────────────────────────────────────────────────────────────────
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const Color _activeBlue = Color(0xFF2A5BD7);
  static const Color _inactiveGrey = Color(0xFF8A8A8A);

  static const List<_NavItemData> _items = [
    _NavItemData(label: 'home', icon: Icons.home_rounded),
    _NavItemData(label: 'accident', icon: Icons.directions_car),
    _NavItemData(label: 'history', icon: Icons.description_outlined),
    _NavItemData(label: 'claim', icon: Icons.assignment_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final itemWidth = ((sw - 44 - 32) / 4).clamp(52.0, 76.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 68,
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
                children: List.generate(
                  _items.length,
                  (i) => _NavItem(
                    data: _items[i],
                    active: currentIndex == i,
                    width: itemWidth,
                    onTap: () => onTap(i),
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

// ─────────────────────────────────────────────────────────────────────
// Internal data class
// ─────────────────────────────────────────────────────────────────────
class _NavItemData {
  final String label;
  final IconData icon;
  const _NavItemData({required this.label, required this.icon});
}

// ─────────────────────────────────────────────────────────────────────
// Individual nav item
// ─────────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool active;
  final double width;
  final VoidCallback onTap;
  final Color activeColor;
  final Color inactiveColor;

  const _NavItem({
    required this.data,
    required this.active,
    required this.width,
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

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
            // ✅ AnimatedScale reacts to active bool directly
            // Works across screen navigations unlike TweenAnimationBuilder
            AnimatedScale(
              scale: active ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Icon(
                data.icon,
                size: 22,
                color: active ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: width < 65 ? 10 : 11,
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
