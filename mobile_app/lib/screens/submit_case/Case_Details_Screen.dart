import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/report_service.dart';
import '../report/report_screen.dart';
import 'photo_preview_screen.dart';

class CaseDetailsScreen extends StatefulWidget {
  final String caseId;

  const CaseDetailsScreen({super.key, required this.caseId});

  @override
  State<CaseDetailsScreen> createState() => _CaseDetailsScreenState();
}

class _CaseDetailsScreenState extends State<CaseDetailsScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF1E3A6E);
  static const Color _navy = Color(0xFF061943);

  bool _isGeneratingReport = false;

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
  static const Map<String, String> _severityLabelAr = {
    'minor': 'ضرر بسيط',
    'moderate': 'ضرر متوسط',
    'severe': 'ضرر بليغ',
  };

  static const Map<String, Color> _severityColor = {
    'minor': Color(0xFFF59E0B),
    'moderate': Color(0xFFEA580C),
    'severe': Colors.red,
  };

  // ── Cost breakdown helpers ────────────────────────────────────────────────
  // damageType/part come from the backend's fixed vocabulary (labor_hours_lookup.py
  // / part_association_service.py) — an unrecognized value falls back to itself.
  static const Map<String, String> _damageTypeLabelAr = {
    'dent': 'انبعاج',
    'scratch': 'خدش',
    'crack': 'تشقق',
    'glass': 'كسر زجاج',
    'lamp': 'كسر مصباح',
    'tire': 'ضرر إطار',
  };

  static const Map<String, String> _partLabelAr = {
    'door': 'الباب',
    'front_bumper': 'الصدام الأمامي',
    'back_bumper': 'الصدام الخلفي',
    'fender': 'الرفرف',
    'hood': 'غطاء المحرك',
    'trunk': 'الصندوق الخلفي',
    'roof': 'السقف',
    'sill': 'العتبة الجانبية',
    'front_glass': 'الزجاج الأمامي',
    'back_glass': 'الزجاج الخلفي',
    'lamp': 'المصباح',
    'wheel': 'الإطار',
  };

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

  // ── Cost section ─────────────────────────────────────────────────────────
  // Gated on the PRESENCE of estimatedCostSar, not on `status` — the backend
  // deliberately pins status back to 'تم الفحص' regardless of whether the cost
  // step succeeded, so status alone can't tell us whether an estimate exists.
  Widget _costSection(Map<String, dynamic> caseData) {
    final dynamic totalRaw = caseData['estimatedCostSar'];
    if (totalRaw is! num) {
      return const SizedBox.shrink();
    }

    final costConfidence =
        (caseData['costConfidence'] as Map<String, dynamic>?) ?? {};
    final String? levelAr = costConfidence['level_ar'] as String?;
    final String? recommendationAr =
        costConfidence['recommendation_ar'] as String?;

    return _sectionCard(
      title: 'التكلفة التقديرية',
      children: [
        _infoBox('الإجمالي التقديري', '$totalRaw ريال'),
        if (levelAr != null && levelAr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: _textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (recommendationAr != null && recommendationAr.isNotEmpty)
                        ? 'مستوى ثقة التقدير: $levelAr — $recommendationAr'
                        : 'مستوى ثقة التقدير: $levelAr',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1, color: Color(0xFFE8EEF7)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'تفاصيل الأضرار',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: _textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _costLineItemsList(),
      ],
    );
  }

  // Per-damage breakdown, alongside the total — lets the user see WHAT the
  // estimate is made of (door dent, front bumper scratch, ...) rather than
  // just a single number, matching how the app already surfaces per-image
  // severity rather than only an overall one.
  Widget _costLineItemsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .collection('images')
          .snapshots(),
      builder: (context, imagesSnap) {
        final imageDocs = imagesSnap.data?.docs ?? [];
        final damagedImageIds = imageDocs
            .where(
              (doc) =>
                  (doc.data() as Map<String, dynamic>)['hasDamage'] == true,
            )
            .map((doc) => doc.id)
            .toList();

        if (damagedImageIds.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: damagedImageIds
              .map((imageId) => _costItemsForImage(imageId))
              .toList(),
        );
      },
    );
  }

  // costItems with a null lineCostSar (unassigned / no matching labor-hours
  // row) are left off this list — those are internal review signals, not
  // something to show a customer as an unexplained blank line.
  Widget _costItemsForImage(String imageId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .collection('images')
          .doc(imageId)
          .collection('costItems')
          .snapshots(),
      builder: (context, itemsSnap) {
        final itemDocs = itemsSnap.data?.docs ?? [];
        final pricedItems = itemDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['lineCostSar'] is num;
        }).toList();

        if (pricedItems.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: pricedItems.map((doc) {
            final item = doc.data() as Map<String, dynamic>;
            final String partKey = item['part']?.toString() ?? '';
            final String damageKey = item['damageType']?.toString() ?? '';
            final String partLabel = _partLabelAr[partKey] ?? partKey;
            final String damageLabel =
                _damageTypeLabelAr[damageKey] ?? damageKey;
            final num cost = item['lineCostSar'] as num;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      '$partLabel — $damageLabel',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$cost ريال',
                    style: const TextStyle(
                      color: _textDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _openReportScreen({
    required String pdfUrl,
    required String reportNumber,
  }) async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportScreen(pdfUrl: pdfUrl, reportNumber: reportNumber),
      ),
    );
  }

  Future<void> _handleReportButton({
    required String? existingPdfUrl,
    required String? existingReportNumber,
  }) async {
    if (_isGeneratingReport) return;

    final savedPdfUrl = existingPdfUrl?.trim() ?? '';

    if (savedPdfUrl.isNotEmpty) {
      await _openReportScreen(
        pdfUrl: savedPdfUrl,
        reportNumber: existingReportNumber?.trim() ?? '',
      );
      return;
    }

    setState(() {
      _isGeneratingReport = true;
    });

    try {
      final result = await ReportService.generateReport(caseId: widget.caseId);

      if (!mounted) return;

      await _openReportScreen(
        pdfUrl: result.pdfUrl,
        reportNumber: result.reportNumber,
      );
    } catch (error) {
      if (!mounted) return;

      final message = error.toString().replaceFirst('Exception: ', '').trim();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'تعذر إنشاء التقرير' : message,
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingReport = false;
        });
      }
    }
  }

  Widget _reportButton({
    required String status,
    required String? reportPdfUrl,
    required String? reportNumber,
  }) {
    if (status != 'تم المراجعة') {
      return const SizedBox.shrink();
    }

    final hasExistingReport =
        reportPdfUrl != null && reportPdfUrl.trim().isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isGeneratingReport
            ? null
            : () => _handleReportButton(
                existingPdfUrl: reportPdfUrl,
                existingReportNumber: reportNumber,
              ),
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: _primaryBlue,
          disabledBackgroundColor: const Color(0xFF93C5FD),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: _isGeneratingReport
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                hasExistingReport ? 'عرض التقرير' : 'إنشاء التقرير',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        automaticallyImplyLeading: false,
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
            .doc(widget.caseId)
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
          final String status = caseData['status']?.toString() ?? '';

          debugPrint(
            '[caseDebug] caseId=${widget.caseId} rawStatus="$status" '
            'length=${status.length} runes=${status.runes.toList()} '
            'matchesLiteral=${status == 'تم المراجعة'} '
            'reportId=${caseData['reportId']}',
          );

          final String? reportPdfUrl = caseData['reportPdfUrl']?.toString();
          final String? reportNumber = caseData['reportNumber']?.toString();

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
                  children: [_infoBox('رقم الطلب', widget.caseId, ltr: true)],
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
                    final vehicleData =
                        vehicleSnap.hasData && vehicleSnap.data!.exists
                        ? vehicleSnap.data!.data() as Map<String, dynamic>
                        : <String, dynamic>{};

                    return _sectionCard(
                      title: 'معلومات المركبة',
                      children: [
                        _infoBox('ماركة المركبة', vehicleData['make'] ?? '-'),
                        _infoBox('طراز المركبة', vehicleData['model'] ?? '-'),
                        _infoBox(
                          'السنة',
                          vehicleData['year']?.toString() ?? '-',
                        ),
                        _infoBox('اللون', vehicleData['color'] ?? '-'),
                        _infoBox(
                          'رقم اللوحة',
                          vehicleData['arabicPlateNumber'] ??
                              vehicleData['plateNumber'] ??
                              '-',
                        ),
                        _infoBox(
                          'رقم الهيكل',
                          vehicleData['chassisNumber'] ?? '-',
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

                if (caseData['estimatedCostSar'] is num) ...[
                  const SizedBox(height: 16),
                  _costSection(caseData),
                ],

                if (status == 'تم المراجعة' || status == 'تم الفحص') ...[
                  const SizedBox(height: 16),
                  _reportButton(
                    status: status,
                    reportPdfUrl: reportPdfUrl,
                    reportNumber: reportNumber,
                  ),
                ],
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
          .doc(widget.caseId)
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

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('accidentCase')
              .doc(widget.caseId)
              .snapshots(),
          builder: (context, caseSnap) {
            final caseData =
                caseSnap.data?.data() as Map<String, dynamic>? ?? {};

            final String status = caseData['status'] ?? '';

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
                  _overallSeverityBox(caseData['overallSeverity'] as String?),
                  SizedBox(
                    height: 142,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: processedImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final item =
                            processedImages[index].data()
                                as Map<String, dynamic>;

                        final bool hasDamage = item['hasDamage'] ?? false;

                        final String? severity = item['severity'] as String?;

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
                      final imageData =
                          images[index].data() as Map<String, dynamic>;

                      final url = imageData['downloadUrl'] ?? '';

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
