import 'package:flutter/material.dart';
import 'dart:ui';
import '../home/home_screen.dart';
import '../submit_case/submit_case_screen.dart';

class AppBottomNav extends StatefulWidget {
  const AppBottomNav({super.key});

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  int _currentIndex = 0;

  static const Color _activeBlue = Color(0xFF2A5BD7);
  static const Color _inactiveGrey = Color(0xFF8A8A8A);

  static const List<_NavItemData> _items = [
    _NavItemData(label: 'الرئيسية', icon: Icons.home_rounded),
    _NavItemData(label: 'حادث', icon: Icons.directions_car),
    _NavItemData(label: 'السجلات', icon: Icons.description_outlined),
    _NavItemData(label: 'الاعتراضات', icon: Icons.assignment_outlined),
  ];

  final List<Widget> _pages = [
    const HomeScreen(),
    const SubmitCaseScreen(),
    const Scaffold(body: Center(child: Text('History - Coming Soon'))),
    const Scaffold(body: Center(child: Text('Claim - Coming Soon'))),
  ];

  void _onTap(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // الصفحات
          IndexedStack(index: _currentIndex, children: _pages),
          // الناف بار فوق المحتوى
          Positioned(bottom: 0, left: 0, right: 0, child: _buildNavBar()),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
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
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(
                  _items.length,
                  (i) => _NavItem(
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

class _NavItemData {
  final String label;
  final IconData icon;
  const _NavItemData({required this.label, required this.icon});
}

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
