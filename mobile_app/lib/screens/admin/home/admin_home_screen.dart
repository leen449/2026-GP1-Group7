import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../home/modify_screen.dart';

enum _AdminStatusView { pending, approved }

enum _ChartPeriod { sixMonths, twelveMonths, thisYear }

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _borderColor = Color(0xFFE8EEF7);
  static const Color _softBlue = Color(0xFFEAF2FF);

  _AdminStatusView _selectedStatus = _AdminStatusView.pending;
  _ChartPeriod _casesPeriod = _ChartPeriod.sixMonths;
  _ChartPeriod _objectionsPeriod = _ChartPeriod.sixMonths;

  String _adminName = '';

  @override
  void initState() {
    super.initState();
    _loadAdminName();
  }

 Future<void> _loadAdminName() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final phone = user.phoneNumber;
  if (phone == null || phone.isEmpty) return;

  final query = await FirebaseFirestore.instance
      .collection('users')
      .where('phoneNumber', isEqualTo: phone)
      .limit(1)
      .get();

  if (!mounted || query.docs.isEmpty) return;

  setState(() {
    _adminName = (query.docs.first.data()['name'] ?? '').toString();
  });
}

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
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
                  ).then((_) => _loadAdminName());
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 18, 18, bottomPad + 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _topHeader(),
              const SizedBox(height: 22),
              _statusSelector(),
              const SizedBox(height: 20),
              _summarySection(),
              const SizedBox(height: 20),
              _chartSection(
                title: 'معدل الحالات',
                collection: 'accidentCase',
                period: _casesPeriod,
                onPeriodChanged: (value) {
                  if (value == null) return;
                  setState(() => _casesPeriod = value);
                },
                isCase: true,
              ),
              const SizedBox(height: 18),
              _chartSection(
                title: 'معدل الاعتراضات',
                collection: 'objection',
                period: _objectionsPeriod,
                onPeriodChanged: (value) {
                  if (value == null) return;
                  setState(() => _objectionsPeriod = value);
                },
                isCase: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topHeader() {
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
                  _adminName.isEmpty ? 'مرحباً!' : 'مرحباً، $_adminName!',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'لوحة تحكم الإدارة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 15,
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

  Widget _statusSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: _statusButton(
              title: 'المعلقة',
              value: _AdminStatusView.pending,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _statusButton(
              title: 'المعتمدة',
              value: _AdminStatusView.approved,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusButton({
    required String title,
    required _AdminStatusView value,
  }) {
    final selected = _selectedStatus == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: selected ? _primaryBlue : _textMuted,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _summarySection() {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Expanded(
          child: _countCard(
            title: 'إجمالي الحالات',
            icon: Icons.directions_car_filled_rounded,
            collection: 'accidentCase',
            isCase: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _countCard(
            title: 'إجمالي الاعتراضات',
            icon: Icons.assignment_outlined,
            collection: 'objection',
            isCase: false,
          ),
        ),
      ],
    );
  }

  Widget _countCard({
    required String title,
    required IconData icon,
    required String collection,
    required bool isCase,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final count = docs.where((doc) {
          final data = doc.data();
          return _matchesSelectedStatus(data, isCase: isCase);
        }).length;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: _primaryBlue, size: 23),
              ),
              const SizedBox(height: 18),
              Text(
                snapshot.connectionState == ConnectionState.waiting
                    ? '—'
                    : '$count',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartSection({
    required String title,
    required String collection,
    required _ChartPeriod period,
    required ValueChanged<_ChartPeriod?> onPeriodChanged,
    required bool isCase,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              _periodDropdown(period, onPeriodChanged),
            ],
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'حسب الشهر',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: _textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection(collection).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 190,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final buckets = _buildMonthlyBuckets(
                snapshot.data?.docs ?? const [],
                period: period,
                isCase: isCase,
              );

              return _MonthlyLineChart(data: buckets);
            },
          ),
        ],
      ),
    );
  }

  Widget _periodDropdown(
    _ChartPeriod value,
    ValueChanged<_ChartPeriod?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _pageBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_ChartPeriod>(
          value: value,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _textMuted,
            size: 20,
          ),
          borderRadius: BorderRadius.circular(14),
          style: const TextStyle(
            color: _textDark,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
          items: const [
            DropdownMenuItem(
              value: _ChartPeriod.sixMonths,
              child: Text('آخر 6 أشهر', textDirection: TextDirection.rtl),
            ),
            DropdownMenuItem(
              value: _ChartPeriod.twelveMonths,
              child: Text('آخر 12 شهرًا', textDirection: TextDirection.rtl),
            ),
            DropdownMenuItem(
              value: _ChartPeriod.thisYear,
              child: Text('هذه السنة', textDirection: TextDirection.rtl),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  bool _matchesSelectedStatus(
    Map<String, dynamic> data, {
    required bool isCase,
  }) {
    final rawStatus = (isCase ? data['status'] : data['objectionStatus'])
        ?.toString()
        .trim();
    final status = rawStatus ?? '';

    if (isCase) {
      if (_selectedStatus == _AdminStatusView.pending) {
        // A case becomes actionable for the admin after the automated analysis
        // finishes and the backend marks it as "تم الفحص".
        return status == 'تم الفحص';
      }

      return status == 'تمت المراجعة' || status == 'valid';
    }

    if (_selectedStatus == _AdminStatusView.pending) {
      return status == 'قيد المراجعة' || status == 'pending';
    }

    // The current user-side code already treats rejected objections separately.
    // Positive/approved labels are kept here in one place so the admin objection
    // page can use the same final value when it is implemented.
    return status == 'مقبول' ||
        status == 'مقبولة' ||
        status == 'تمت الموافقة' ||
        status == 'تم قبول الاعتراض' ||
        status == 'approved';
  }

  List<_MonthPoint> _buildMonthlyBuckets(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required _ChartPeriod period,
    required bool isCase,
  }) {
    final months = _monthsForPeriod(period);
    final counts = <String, int>{
      for (final month in months) _monthKey(month): 0,
    };

    for (final doc in docs) {
      final data = doc.data();
      if (!_matchesSelectedStatus(data, isCase: isCase)) continue;

      final createdAt = data['createdAt'];
      if (createdAt is! Timestamp) continue;

      final date = createdAt.toDate();
      final key = _monthKey(DateTime(date.year, date.month));
      if (counts.containsKey(key)) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    return months
        .map(
          (month) => _MonthPoint(
            label: _monthLabel(month),
            value: (counts[_monthKey(month)] ?? 0).toDouble(),
          ),
        )
        .toList();
  }

  List<DateTime> _monthsForPeriod(_ChartPeriod period) {
    final now = DateTime.now();

    if (period == _ChartPeriod.thisYear) {
      return List.generate(
        now.month,
        (index) => DateTime(now.year, index + 1),
      );
    }

    final count = period == _ChartPeriod.sixMonths ? 6 : 12;
    return List.generate(count, (index) {
      final offset = count - 1 - index;
      return DateTime(now.year, now.month - offset);
    });
  }

  String _monthKey(DateTime date) => '${date.year}-${date.month}';

  String _monthLabel(DateTime date) {
  const labels = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  return labels[date.month - 1];
}
}

class _MonthPoint {
  const _MonthPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class _MonthlyLineChart extends StatelessWidget {
  const _MonthlyLineChart({required this.data});

  final List<_MonthPoint> data;

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<double>(
      0,
      (current, point) => point.value > current ? point.value : current,
    );

    return SizedBox(
      height: 205,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _LineChartPainter(
                values: data.map((e) => e.value).toList(),
                maxValue: maxValue,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: data
                .map(
                  (point) => Expanded(
                    child: Text(
                      point.label,
                      textAlign: TextAlign.center,
                     maxLines: 1,
softWrap: false,
overflow: TextOverflow.visible,
style: TextStyle(
  color: const Color(0xFF8B97AA),
  fontSize: data.length > 6 ? 8.0 : 9.5,
  fontWeight: FontWeight.w600,
),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values, required this.maxValue});

  final List<double> values;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    const primaryBlue = Color(0xFF2563EB);
    const gridColor = Color(0xFFE8EEF7);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    final linePaint = Paint()
      ..color = primaryBlue
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryBlue.withOpacity(0.18),
          primaryBlue.withOpacity(0.01),
        ],
      ).createShader(Offset.zero & size);

    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final normalized = values[i] / safeMax;
      final y = size.height - (normalized * (size.height * 0.82)) - 8;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    final lastX = values.length == 1 ? size.width / 2 : size.width;
    fillPath.lineTo(lastX, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final pointBorderPaint = Paint()
      ..color = primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final normalized = values[i] / safeMax;
      final y = size.height - (normalized * (size.height * 0.82)) - 8;
      canvas.drawCircle(Offset(x, y), 4.2, pointPaint);
      canvas.drawCircle(Offset(x, y), 4.2, pointBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.maxValue != maxValue || oldDelegate.values != values;
  }
}
