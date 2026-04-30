import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CaseDetailsScreen extends StatelessWidget {
  final String caseId;

  const CaseDetailsScreen({super.key, required this.caseId});

  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _navy = Color(0xFF061943);

  // ── Matches HomeScreen's _centerInfoBox ──────────────────────────────────
  Widget _infoBox(String title, String value, {bool ltr = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _pageBg,
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
              color: _textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value.trim().isEmpty ? '—' : value,
                textAlign: ltr ? TextAlign.left : TextAlign.right,
                style: const TextStyle(
                  color: _textDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card matching HomeScreen's card style ─────────────────────────
  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // ── Status badge — same logic as HomeScreen ───────────────────────────────
  Widget _statusBadge(String status) {
    final s = status.toLowerCase().trim();
    String label;
    Color bg;
    Color fg;
    IconData icon;

    if (s == 'approved' || s == 'completed') {
      label = 'مكتمل';
      bg = const Color(0xFFE7F8EF);
      fg = const Color(0xFF159B55);
      icon = Icons.check_circle_outline_rounded;
    } else if (s == 'pending') {
      label = 'قيد المراجعة';
      bg = const Color(0xFFEAF1FF);
      fg = const Color(0xFF2E63D9);
      icon = Icons.hourglass_empty_rounded;
    } else if (s == 'ocr_failed') {
      label = 'فشل الفحص';
      bg = const Color(0xFFFFEEF0);
      fg = const Color(0xFFE33B4E);
      icon = Icons.warning_amber_rounded;
    } else {
      label = 'قيد التحليل';
      bg = const Color(0xFFFFF1E6);
      fg = const Color(0xFFE27A2E);
      icon = Icons.access_time_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        automaticallyImplyLeading: false, // remove the default left arrow
        leading: const SizedBox(),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded, color: _textDark),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text(
          'تفاصيل الطلب',
          style: TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('accidentCase')
            .doc(caseId)
            .snapshots(),
        builder: (context, caseSnap) {
          if (caseSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!caseSnap.hasData || !caseSnap.data!.exists) {
            return const Center(
              child: Text(
                'لم يتم العثور على الطلب',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final caseData = caseSnap.data!.data() as Map<String, dynamic>;
          final vehicleId = caseData['vehicleId'] ?? '';
          final ownerId = caseData['ownerId'] ?? '';
          final najmReport =
              (caseData['najimReport'] as Map<String, dynamic>?) ?? {};
          final status = caseData['status'] ?? '';

          final createdAt = caseData['createdAt'] is Timestamp
              ? (caseData['createdAt'] as Timestamp).toDate()
              : null;
          final createdAtText = createdAt == null
              ? '-'
              : '${createdAt.day}/${createdAt.month}/${createdAt.year}';

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Request summary ──────────────────────────────────────
                _sectionCard(
                  title: 'ملخص الطلب',
                  children: [_infoBox('رقم الطلب', caseId, ltr: true)],
                ),
                const SizedBox(height: 16),

                // ── Personal data ────────────────────────────────────────
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(ownerId)
                      .get(),
                  builder: (context, userSnap) {
                    final userData = userSnap.hasData && userSnap.data!.exists
                        ? userSnap.data!.data() as Map<String, dynamic>
                        : <String, dynamic>{};

                    return _sectionCard(
                      title: 'البيانات الشخصية',
                      children: [
                        _infoBox('الاسم', userData['name'] ?? '-'),
                        _infoBox(
                          'رقم الهوية',
                          userData['nationalID'] ?? '-',
                          ltr: true,
                        ),
                        _infoBox(
                          'رقم الجوال',
                          userData['phoneNumber'] ?? '-',
                          ltr: true,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── Vehicle info ─────────────────────────────────────────
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('vehicles')
                      .doc(vehicleId)
                      .get(),
                  builder: (context, vehicleSnap) {
                    final v = vehicleSnap.hasData && vehicleSnap.data!.exists
                        ? vehicleSnap.data!.data() as Map<String, dynamic>
                        : <String, dynamic>{};

                    return _sectionCard(
                      title: 'معلومات المركبة',
                      children: [
                        _infoBox('ماركة المركبة', v['make'] ?? '-'),
                        _infoBox('طراز المركبة', v['model'] ?? '-'),
                        _infoBox('السنة', v['year']?.toString() ?? '-'),
                        _infoBox('اللون', v['color'] ?? '-'),
                        _infoBox(
                          'رقم اللوحة',
                          v['arabicPlateNumber'] ?? v['plateNumber'] ?? '-',
                        ),
                        _infoBox(
                          'رقم الهيكل',
                          v['chassisNumber'] ?? '-',
                          ltr: true,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── Najm report ──────────────────────────────────────────
                _sectionCard(
                  title: 'تقرير نجم',
                  children: [
                    _infoBox(
                      'رقم الحادث',
                      najmReport['accidentNumber']?.toString() ?? '-',
                      ltr: true,
                    ),
                    _infoBox('تاريخ الحادث', najmReport['accidentDate'] ?? '-'),
                    _infoBox('موقع الضرر', najmReport['damageLocation'] ?? '-'),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Damage images ────────────────────────────────────────
                _imagesSection(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _imagesSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .collection('images')
          .orderBy('uploadedAt')
          .snapshots(),
      builder: (context, imageSnap) {
        if (imageSnap.connectionState == ConnectionState.waiting) {
          return _sectionCard(
            title: 'صور الأضرار',
            children: const [Center(child: CircularProgressIndicator())],
          );
        }

        final images = imageSnap.data?.docs ?? [];

        if (images.isEmpty) {
          return _sectionCard(
            title: 'صور الأضرار',
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'لا توجد صور مرفوعة',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return _sectionCard(
          title: 'صور الأضرار',
          children: [
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final data = images[index].data() as Map<String, dynamic>;
                  final url = data['downloadUrl'] ?? '';

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: _navy,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
