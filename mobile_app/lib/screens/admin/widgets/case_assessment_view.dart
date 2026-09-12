import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../submit_case/photo_preview_screen.dart';

/// Read-only admin view of a case's full AI assessment: case/vehicle/Najm
/// info, per-image detections + affected parts + severity, overall severity,
/// estimated cost, and cost-confidence detail.
///
/// Visual language (colors, card/chip shapes) is copied from
/// `Case_Details_Screen.dart` on purpose — this codebase's convention is that
/// every screen keeps its own private copies of these small style helpers
/// rather than sharing a widgets library, so this file does the same instead
/// of importing that customer-facing screen's private state class.
///
/// `caseId` MUST be the literal `accidentCase` Firestore document ID (not the
/// human-readable `caseID` field some case docs also carry) — callers that
/// only have the human-readable id must resolve it to a doc id first.
///
/// This widget renders a plain [Column] with no [Scaffold]/[ScrollView] of
/// its own, so host screens embed it inside their own scroll view and append
/// their own action buttons below it in the same scroll — no nested
/// scrollables, no fixed heights.
class CaseAssessmentView extends StatelessWidget {
  final String caseId;

  const CaseAssessmentView({super.key, required this.caseId});

  // ── Colors (copied from Case_Details_Screen.dart) ────────────────────────
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);

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
    'windshield': 'الزجاج الأمامي أو الخلفي',
    'door_glass': 'زجاج الباب',
    'lamp': 'المصباح',
    'wheel': 'الإطار',
  };

  // Internal English flags the backend attaches to unresolved/uncertain
  // pricing decisions (see cost_estimation_services.py / part_association_
  // service.py) — translated for the admin instead of shown raw.
  static const Map<String, String> _costFactorLabelAr = {
    'missing_image_severity': 'لم يتم تحديد شدة الضرر لهذه الصورة',
    'invalid_image_severity': 'قيمة شدة ضرر غير صالحة لهذه الصورة',
    'no_hours': 'لا توجد ساعات عمل معتمدة لهذا التصنيف',
    'unassigned': 'لم يتم ربط هذا الضرر بموقع مؤكد',
    'unassigned_admin_review':
        'لم يتحدد الجزء المتضرر تلقائيًا — يتطلب تحديدًا يدويًا',
    'vehicle_value_unavailable': 'قيمة المركبة السوقية غير متوفرة',
    'low_cost_confidence': 'ثقة منخفضة في التقدير الإجمالي للتكلفة',
    'incomplete_cost_estimate': 'تقدير التكلفة غير مكتمل',
    'image_cost_failed': 'تعذر حساب تكلفة إحدى الصور',
    'wheel_position_ambiguous_fallback':
        'لم يتحدد موقع الإطار (أمامي/خلفي) — استُخدم متوسط تقديري',
    'glass_no_part_support': 'لم يُؤكَّد موقع كسر الزجاج',
    'glass_ambiguous_part': 'تعدد المواقع المحتملة لكسر الزجاج',
    'centroid_fallback': 'تم تحديد الجزء المتضرر بطريقة تقريبية',
  };

  static String _costFactorLabel(String raw) {
    final mapped = _costFactorLabelAr[raw];
    if (mapped != null) return mapped;
    if (raw.startsWith('prior case')) {
      return 'يوجد ضرر مشابه في حالة سابقة لنفس المالك والمركبة';
    }
    return raw;
  }

  // ── Generic building blocks (same shape as Case_Details_Screen.dart) ────

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

  Widget _mutedCaption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          text,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            color: _textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Section 1-4: case / personal / vehicle / Najm ────────────────────────

  Widget _summaryCard(Map<String, dynamic> caseData) {
    final String status = caseData['status']?.toString() ?? '';
    return _sectionCard(
      title: 'ملخص الطلب',
      children: [
        _infoBox('رقم الطلب', caseId, ltr: true),
        _infoBox('حالة الطلب ', status),
      ],
    );
  }

  Widget _personalInfoCard(String ownerId) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(ownerId).get(),
      builder: (context, snap) {
        final data = snap.hasData && snap.data!.exists
            ? snap.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};
        return _sectionCard(
          title: 'البيانات الشخصية',
          children: [
            _infoBox('الاسم', data['name'] ?? '-'),
            _infoBox('رقم الهوية', data['nationalID'] ?? '-', ltr: true),
            _infoBox('رقم الجوال', data['phoneNumber'] ?? '-', ltr: true),
          ],
        );
      },
    );
  }

  Widget _vehicleInfoCard(String vehicleId) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('vehicles')
          .doc(vehicleId)
          .get(),
      builder: (context, snap) {
        final data = snap.hasData && snap.data!.exists
            ? snap.data!.data() as Map<String, dynamic>
            : <String, dynamic>{};
        return _sectionCard(
          title: 'معلومات المركبة',
          children: [
            _infoBox('ماركة المركبة', data['make'] ?? '-'),
            _infoBox('طراز المركبة', data['model'] ?? '-'),
            _infoBox('السنة', data['year']?.toString() ?? '-'),
            _infoBox('اللون', data['color'] ?? '-'),
            _infoBox(
              'رقم اللوحة',
              data['arabicPlateNumber'] ?? data['plateNumber'] ?? '-',
            ),
            _infoBox('رقم الهيكل', data['chassisNumber'] ?? '-', ltr: true),
          ],
        );
      },
    );
  }

  Widget _najmCard(Map<String, dynamic> najmReport) {
    return _sectionCard(
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
    );
  }

  // ── Section 5: per-image damage analysis ─────────────────────────────────

  Widget _imagesAnalysisCard(
    BuildContext context,
    Map<String, dynamic> caseData,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .collection('images')
          .snapshots(),
      builder: (context, imagesSnap) {
        final images = imagesSnap.data?.docs ?? [];

        if (images.isEmpty) {
          return _sectionCard(
            title: 'نتائج تحليل الأضرار',
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
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return _sectionCard(
          title: 'نتائج تحليل الأضرار',
          children: [
            _overallSeverityBox(caseData['overallSeverity'] as String?),
            ...images.map((doc) => _imageBlock(context, doc)),
          ],
        );
      },
    );
  }

  Widget _imageBlock(BuildContext context, QueryDocumentSnapshot imageDoc) {
    final item = imageDoc.data() as Map<String, dynamic>;
    final bool hasDamage = item['hasDamage'] ?? false;
    final String? severity = item['severity'] as String?;
    final dynamic severityConfidence = item['severityConfidence'];
    final dynamic laborCost = item['estimatedLaborCostSar'];
    final String url = hasDamage
        ? (item['annotatedImage'] ?? item['downloadUrl'] ?? '')
        : (item['downloadUrl'] ?? '');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _pageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: url.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PhotoPreviewScreen(imageUrl: url),
                        ),
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: url.isEmpty
                      ? Container(
                          width: 78,
                          height: 78,
                          color: const Color(0xFFEAF2FF),
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: Color(0xFF0B4A7D),
                          ),
                        )
                      : Image.network(
                          url,
                          width: 78,
                          height: 78,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 78,
                            height: 78,
                            color: const Color(0xFFEAF2FF),
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFF0B4A7D),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Text(
                          hasDamage ? 'ضرر مكتشف' : 'سليمة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hasDamage ? Colors.red : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _severityChip(severity),
                      ],
                    ),
                    if (severityConfidence is num) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ثقة تصنيف الشدة: ${(severityConfidence * 100).round()}%',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: _textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (laborCost is num) ...[
                      const SizedBox(height: 4),
                      Text(
                        'تكلفة الصورة: $laborCost ريال',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasDamage) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE8EEF7)),
            const SizedBox(height: 8),
            _mutedCaption('الأضرار المكتشفة'),
            _detectionsList(imageDoc.reference),
            const SizedBox(height: 10),
            _mutedCaption('الأجزاء المتضررة والتكلفة'),
            _costItemsList(imageDoc.reference),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _detectionsList(DocumentReference imageRef) {
    return StreamBuilder<QuerySnapshot>(
      stream: imageRef.collection('detections').snapshots(),
      builder: (context, snap) {
        final docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? []);
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'لا توجد أضرار مسجلة',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
          );
        }
        docs.sort((a, b) {
          final ca = (a.data() as Map<String, dynamic>)['confidence'];
          final cb = (b.data() as Map<String, dynamic>)['confidence'];
          final da = ca is num ? ca.toDouble() : 0.0;
          final db = cb is num ? cb.toDouble() : 0.0;
          return db.compareTo(da);
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final String label = d['label']?.toString() ?? '-';
            final dynamic confidence = d['confidence'];
            final String confText = confidence is num
                ? '${(confidence * 100).round()}%'
                : '-';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    'ثقة: $confText',
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  Widget _costItemsList(DocumentReference imageRef) {
    return StreamBuilder<QuerySnapshot>(
      stream: imageRef.collection('costItems').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'لا توجد عناصر تكلفة بعد',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: _textMuted, fontSize: 12),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: docs.map((doc) {
            final item = doc.data() as Map<String, dynamic>;
            final String partKey = item['part']?.toString() ?? '';
            final String damageKey = item['damageType']?.toString() ?? '';
            final String partLabel =
                _partLabelAr[partKey] ??
                (partKey.isEmpty ? 'غير محدد' : partKey);
            final String damageLabel =
                _damageTypeLabelAr[damageKey] ??
                (damageKey.isEmpty ? 'غير محدد' : damageKey);
            final dynamic cost = item['lineCostSar'];
            final List<dynamic> flags = (item['flags'] as List?) ?? const [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
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
                        cost is num ? '$cost ريال' : 'لم يتم تسعيرها',
                        style: TextStyle(
                          color: cost is num ? _textDark : Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (flags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        flags
                            .map((f) => _costFactorLabel(f.toString()))
                            .join('، '),
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.red, fontSize: 10),
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

  // ── Section 6: estimated cost total ──────────────────────────────────────

  Widget _costTotalCard(Map<String, dynamic> caseData) {
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
            padding: const EdgeInsets.only(bottom: 4),
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
    );
  }

  // ── Section 7: confidence detail ─────────────────────────────────────────

  Widget _confidenceDetailCard(Map<String, dynamic> caseData) {
    final costConfidence =
        (caseData['costConfidence'] as Map<String, dynamic>?) ?? {};
    if (costConfidence.isEmpty) {
      return const SizedBox.shrink();
    }

    final dynamic score = costConfidence['confidence_score'];
    final String? levelAr = costConfidence['level_ar'] as String?;
    final bool requiresReview =
        costConfidence['requires_admin_review'] == true ||
        caseData['needsAdminReview'] == true;
    final List<dynamic> deductions =
        (costConfidence['deductions'] as List?) ?? const [];
    final List<dynamic> reviewReasons =
        (caseData['reviewReasons'] as List?) ?? const [];

    return _sectionCard(
      title: 'تفاصيل الثقة',
      children: [
        if (score is num) _infoBox('درجة الثقة', '$score / 100'),
        if (levelAr != null && levelAr.isNotEmpty)
          _infoBox('مستوى الثقة', levelAr),
        if (requiresReview)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFFEA580C).withOpacity(0.4),
              ),
            ),
            child: const Text(
              'يتطلب مراجعة الإدارة',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Color(0xFFEA580C),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        if (deductions.isNotEmpty) ...[
          _mutedCaption('أسباب تخفيض الثقة'),
          ...deductions.map((d) {
            final m = d as Map<String, dynamic>;
            final reasonAr = m['reason_ar']?.toString() ?? '-';
            final points = m['points'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '− $points: $reasonAr',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
        ],
        if (reviewReasons.isNotEmpty) ...[
          _mutedCaption('عوامل التكلفة'),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: reviewReasons.map((r) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _pageBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8EEF7)),
                ),
                child: Text(
                  _costFactorLabel(r.toString()),
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(color: _textMuted, fontSize: 10),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .snapshots(),
      builder: (context, caseSnap) {
        if (caseSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!caseSnap.hasData || !caseSnap.data!.exists) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'لم يتم العثور على الحالة',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        final caseData = caseSnap.data!.data() as Map<String, dynamic>;
        final String vehicleId = caseData['vehicleId']?.toString() ?? '';
        final String ownerId = caseData['ownerId']?.toString() ?? '';
        final najmReport =
            (caseData['najimReport'] as Map<String, dynamic>?) ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryCard(caseData),
            const SizedBox(height: 16),
            _personalInfoCard(ownerId),
            const SizedBox(height: 16),
            _vehicleInfoCard(vehicleId),
            const SizedBox(height: 16),
            _najmCard(najmReport),
            const SizedBox(height: 16),
            _imagesAnalysisCard(context, caseData),
            const SizedBox(height: 16),
            _costTotalCard(caseData),
            if (caseData['estimatedCostSar'] is num) const SizedBox(height: 16),
            _confidenceDetailCard(caseData),
          ],
        );
      },
    );
  }
}
