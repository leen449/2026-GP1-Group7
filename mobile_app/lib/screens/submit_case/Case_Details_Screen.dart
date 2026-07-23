import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'photo_preview_screen.dart';

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
                textAlign: TextAlign.right,
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

  // ── Severity helpers ──────────────────────────────────────────────────────
  // [NEW] Severity is written by the backend as one of: minor / moderate /
  // severe, or null when no damage was detected on that image.
  //
  // Colour choice: green is already used for "سليمة" (undamaged), so minor
  // damage uses amber rather than green to avoid reading as "no damage".
  static const Map<String, String> _severityLabelAr = {
    'minor': 'ضرر بسيط',
    'moderate': 'ضرر متوسط',
    'severe': 'ضرر بليغ',
  };

  static const Map<String, Color> _severityColor = {
    'minor': Color(0xFFF59E0B), // amber
    'moderate': Color(0xFFEA580C), // orange
    'severe': Color(0xFFDC2626), // red
  };

  // Small chip shown under each analysed image.
  Widget _severityChip(String? severity) {
    if (severity == null || !_severityLabelAr.containsKey(severity)) {
      return const SizedBox.shrink();
    }

    final color = _severityColor[severity]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        _severityLabelAr[severity]!,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // Case-level severity banner. The backend writes `overallSeverity` as the
  // worst severity across all damaged images.
  Widget _overallSeverityBox(String? overallSeverity) {
    if (overallSeverity == null ||
        !_severityLabelAr.containsKey(overallSeverity)) {
      return const SizedBox.shrink();
    }

    final color = _severityColor[overallSeverity]!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(Icons.speed_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          const Text(
            'مستوى الضرر',
            textDirection: TextDirection.rtl,
            style: TextStyle(color: _textMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _severityLabelAr[overallSeverity]!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status badge — same logic as HomeScreen ───────────────────────────────

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
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: _textDark),
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
      // [1] Read from images subcollection instead of damageAnalysis array
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .collection('images')
          .snapshots(),
      builder: (context, imagesSnap) {
        if (imagesSnap.connectionState == ConnectionState.waiting) {
          return _sectionCard(
            title: 'صور الأضرار',
            children: const [Center(child: CircularProgressIndicator())],
          );
        }

        final images = imagesSnap.data?.docs ?? [];

        // [2] Read case status to determine which scenario to show
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('accidentCase')
              .doc(caseId)
              .snapshots(),
          builder: (context, caseSnap) {
            final caseData =
                caseSnap.data?.data() as Map<String, dynamic>? ?? {};
            final String status = caseData['status'] ?? '';

            // ==========================================
            // SCENARIO 1: AI Analysis is Complete
            // Show the Annotated Gallery
            // ==========================================
            // [3] Check if any image has hasDamage field — means AI processing is done
            final processedImages = images
                .where(
                  (doc) => (doc.data() as Map<String, dynamic>).containsKey(
                    'hasDamage',
                  ),
                )
                .toList();

            if (processedImages.isNotEmpty) {
              return _sectionCard(
                title: 'نتائج تحليل الأضرار',
                children: [
                  // [NEW] Case-level severity, worst across all images.
                  // Renders nothing when overallSeverity is null.
                  _overallSeverityBox(caseData['overallSeverity'] as String?),
                  SizedBox(
                    // [NEW] Raised from 120 to fit the severity chip.
                    height: 142,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: processedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        // [4] Read each image document
                        final item =
                            processedImages[index].data()
                                as Map<String, dynamic>;
                        final bool hasDamage = item['hasDamage'] ?? false;

                        // [NEW] Written by the backend in the same update as
                        // hasDamage, so it is never missing when hasDamage is
                        // present. Null means undamaged, or the severity model
                        // failed on this image.
                        final String? severity = item['severity'] as String?;

                        // [5] Show annotatedImage if damage exists, otherwise originalImage
                        final String url = hasDamage
                            ? (item['annotatedImage'] ??
                                  item['downloadUrl'] ??
                                  '')
                            : (item['downloadUrl'] ?? '');

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PhotoPreviewScreen(imageUrl: url),
                            ),
                          ),
                          child: SizedBox(
                            width: 90,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Stack(
                                  children: [
                                    ClipRRect(
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
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Color(0xFF0B4A7D),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: hasDamage
                                              ? Colors.red
                                              : Colors.green,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.2,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          hasDamage
                                              ? Icons.warning_amber_rounded
                                              : Icons.check,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  hasDamage ? 'ضرر مكتشف' : 'سليمة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: hasDamage
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // [NEW] Severity chip. Collapses to nothing
                                // when severity is null, so undamaged images
                                // are unaffected.
                                if (severity != null) ...[
                                  const SizedBox(height: 4),
                                  _severityChip(severity),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }

            // ==========================================
            // SCENARIO 2: AI is currently processing
            // ==========================================
            final hasAnyImages = images.isNotEmpty;
            final allImagesHaveResult =
                hasAnyImages &&
                images.every((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data.containsKey('hasDamage');
                });

            if (hasAnyImages &&
                !allImagesHaveResult &&
                status != 'تم الفحص' &&
                status != 'فشل الفحص') {
              return _sectionCard(
                title: 'تحليل الأضرار',
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          CircularProgressIndicator(
                            color: Color(0xFF1E3A6E),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'جاري تحليل الصور باستخدام الذكاء الاصطناعي...',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            // ==========================================
            // SCENARIO 3: Fallback (AI Failed or no images)
            // ==========================================
            if (images.isEmpty) {
              return _sectionCard(
                title: 'صور الأضرار',
                children: const [
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'لا توجد صور مرفوعة',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // [6] Show original images if AI failed
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
                      final imgData =
                          images[index].data() as Map<String, dynamic>;
                      final url = imgData['downloadUrl'] ?? '';

                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PhotoPreviewScreen(imageUrl: url),
                          ),
                        ),
                        child: ClipRRect(
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
                                color: Color(0xFF0B4A7D),
                              ),
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
      },
    );
  }
}
