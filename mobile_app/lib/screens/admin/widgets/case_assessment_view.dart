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

  // Optional callback used by the admin review screen.
  final void Function(String imageId, String imageUrl, int imageNumber)?
  onEditImage;

  const CaseAssessmentView({super.key, required this.caseId, this.onEditImage});

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
    // Cost rule v2 identity labels (2026-11-07) -- see
    // backend_api/services/report_pdf_service.py's _PART_LABEL_AR comment.
    'window': 'زجاج الباب',
    'glass_ambiguous': 'زجاج (الموقع غير مؤكد)',
  };

  /// cost_v2's panel_id is "{caseId}:{part}" or, for the per-image identity
  /// fallback, "{caseId}:{tableKey}:{imageId}" -- either way the part/hours-
  /// key name is the second colon-separated segment. Mirrors
  /// routes/reports.py's _part_from_panel_id exactly.
  static String _partFromPanelId(String? panelId) {
    final parts = (panelId ?? '').split(':');
    return parts.length >= 2 ? parts[1] : (panelId ?? '');
  }

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

  // Every section on this page is an accordion card: collapsed by default,
  // showing only the title plus a short one-line `subtitle` preview so the
  // reviewer can scan the whole case (status, name, plate, total cost, ...)
  // without opening every card, then tap to expand the one they need.
  Widget _sectionCard({
    required String title,
    String? subtitle,
    bool needsAttention = false,
    required List<Widget> children,
  }) {
    return _CollapsibleCard(
      title: title,
      subtitle: subtitle,
      needsAttention: needsAttention,
      initiallyExpanded: false,
      children: children,
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
      subtitle: status.isEmpty ? null : status,
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
        final String name = data['name']?.toString() ?? '';
        return _sectionCard(
          title: 'البيانات الشخصية',
          subtitle: name.isEmpty ? null : name,
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
        final String make = data['make']?.toString() ?? '';
        final String model = data['model']?.toString() ?? '';
        final String vehicleSubtitle = [
          make,
          model,
        ].where((s) => s.isNotEmpty).join(' ');
        return _sectionCard(
          title: 'معلومات المركبة',
          subtitle: vehicleSubtitle.isEmpty ? null : vehicleSubtitle,
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
    final String damageLocation =
        najmReport['damageLocation']?.toString() ?? '';
    return _sectionCard(
      title: 'تقرير نجم',
      subtitle: damageLocation.isEmpty ? null : damageLocation,
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
            subtitle: 'لا توجد صور مرفوعة',
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

        final String? overallSeverity = caseData['overallSeverity'] as String?;
        final String severityLabel = overallSeverity == null
            ? ''
            : (_severityLabelAr[overallSeverity] ?? '');
        final String imagesSubtitle = [
          '${images.length} صور',
          if (severityLabel.isNotEmpty) severityLabel,
        ].join(' — ');

        final bool isV2Display =
            caseData['displayCostSar'] is num &&
            caseData['displayCostSource'] == 'v2';

        return _sectionCard(
          title: 'نتائج تحليل الأضرار',
          subtitle: imagesSubtitle,
          children: [
            _overallSeverityBox(overallSeverity),
            ...images.asMap().entries.map(
              (entry) => _imageBlock(
                context,
                entry.value,
                entry.key + 1,
                isV2Display,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _imageBlock(
    BuildContext context,
    QueryDocumentSnapshot imageDoc,
    int imageNumber,
    bool isV2Display,
  ) {
    final item = imageDoc.data() as Map<String, dynamic>;
    final String imageId = imageDoc.id;

    final String originalImageUrl = item['downloadUrl']?.toString() ?? '';
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
                      // pen, then spacer, then the severity chip — explicit
                      // rtl so the pen (listed first) reliably lands on the
                      // RIGHT regardless of screen width. This app has no
                      // app-wide RTL (no locale/supportedLocales configured
                      // in main.dart), so this must be stated here rather
                      // than assumed from ambient direction.
                      textDirection: TextDirection.rtl,
                      children: [
                        // Shown regardless of hasDamage — a "سليمة"
                        // prediction can be a false negative (e.g. a blurry
                        // photo, see CLAUDE.local.md), and gating this on
                        // hasDamage left the admin with no way to reach
                        // EditDamagesScreen and add the missed damage.
                        if (onEditImage != null)
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: IconButton(
                              tooltip: hasDamage
                                  ? 'تعديل أضرار الصورة'
                                  : 'إضافة ضرر لهذه الصورة',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                onEditImage!(
                                  imageId,
                                  originalImageUrl.isNotEmpty
                                      ? originalImageUrl
                                      : url,
                                  imageNumber,
                                );
                              },
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFF1E3A6E),
                                size: 20,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // No-damage indicator only — the "ضرر مكتشف" label
                        // was intentionally removed; severity is null for
                        // undamaged images so the chip renders nothing here,
                        // leaving this as the only content. Flexible keeps
                        // it safe at any width, matching the rest of the row.
                        if (!hasDamage)
                          const Flexible(
                            child: Text(
                              'سليمة',
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        // severityChip already ellipsizes internally, so
                        // it's safe standalone at any width.
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
                    if (laborCost is num) ...[const SizedBox(height: 4)],
                  ],
                ),
              ),
            ],
          ),
          if (hasDamage) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE8EEF7)),
            const SizedBox(height: 8),
            // When cost rule v2 is the displayed total, these per-item costs
            // are v1 figures kept only so the admin can review/edit what the
            // model detected on this image -- they no longer sum to the
            // total above (see the "تفصيل التكلفة" breakdown in section 6).
            _mutedCaption(
              isV2Display
                  ? 'الأجزاء المتضررة (بيانات النموذج، للتعديل)'
                  : 'الأجزاء المتضررة والتكلفة',
            ),
            _costItemsList(imageDoc.reference),
            const SizedBox(height: 4),
          ],
        ],
      ),
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

        // Grouped by origin instead of tagging every single line — with
        // several damages in the same state on one image, repeating the
        // same badge on every line is just noise. One caption per group
        // says it once.
        final removedDocs = <QueryDocumentSnapshot>[];
        final addedDocs = <QueryDocumentSnapshot>[];
        final editedDocs = <QueryDocumentSnapshot>[];
        // One fixed, always-present list of every damage the model ever
        // detected (part/type/cost as originally predicted) — untouched,
        // edited, or removed alike. This replaces having a separate
        // "أضرار من النموذج" group for untouched items: since an untouched
        // item's current values already equal its original ones, it only
        // needs to appear here, not in a second list saying the same thing.
        // adminAdded items are excluded: they never had a model prediction.
        final originalDocs = <QueryDocumentSnapshot>[];
        for (final doc in docs) {
          final item = doc.data() as Map<String, dynamic>;
          if (item['removedByAdmin'] == true) {
            removedDocs.add(doc);
          } else if (item['adminAdded'] == true) {
            addedDocs.add(doc);
          } else if (item['adminEdited'] == true) {
            editedDocs.add(doc);
          }
          if (item['adminAdded'] != true && item['originalDamageType'] != null) {
            originalDocs.add(doc);
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (originalDocs.isNotEmpty) ...[
              _mutedCaption('جميع أضرار النموذج الأصلية'),
              ...originalDocs.map(
                (doc) => _originalDetectionTile(
                  doc.data() as Map<String, dynamic>,
                ),
              ),
            ],
            if (editedDocs.isNotEmpty) ...[
              _mutedCaption('أضرار عدّلها المشرف'),
              ...editedDocs.map(
                (doc) => _costItemTile(doc.data() as Map<String, dynamic>),
              ),
            ],
            if (addedDocs.isNotEmpty) ...[
              _mutedCaption('أضرار أضافها المشرف'),
              ...addedDocs.map(
                (doc) => _costItemTile(doc.data() as Map<String, dynamic>),
              ),
            ],
            if (removedDocs.isNotEmpty) ...[
              _mutedCaption('أضرار أزالها المشرف من التسعير'),
              ...removedDocs.map(
                (doc) => _costItemTile(doc.data() as Map<String, dynamic>),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _costItemTile(Map<String, dynamic> item) {
    final bool removed = item['removedByAdmin'] == true;

    final String partKey = item['part']?.toString() ?? '';
    final String damageKey = item['damageType']?.toString() ?? '';
    final String partLabel =
        _partLabelAr[partKey] ?? (partKey.isEmpty ? 'غير محدد' : partKey);
    final String damageLabel =
        _damageTypeLabelAr[damageKey] ??
        (damageKey.isEmpty ? 'غير محدد' : damageKey);
    final dynamic cost = item['lineCostSar'];
    final List<dynamic> flags = (item['flags'] as List?) ?? const [];

    // The model's original prediction for this item (if any) is shown
    // separately in the independent "جميع أضرار النموذج الأصلية" section
    // above instead of repeated here — showing it again per-item would be
    // the same information twice.

    // Two independent model confidences, shown together instead of in a
    // separate "raw detections" list: how sure the damage detector was
    // about the damage type, and how sure the segmentation step was about
    // the part it matched it to. Either can be absent — part confidence in
    // particular isn't a real measured value for lamp/tire (fixed, not
    // detected) or unassigned lines (no match was made at all).
    final dynamic damageConfidence = item['damageConfidence'];
    final dynamic partConfidence = item['partConfidence'];
    final List<String> confidenceParts = [
      if (damageConfidence is num)
        'ثقة الكشف: ${(damageConfidence * 100).round()}%',
      if (partConfidence is num)
        'ثقة تحديد الجزء: ${(partConfidence * 100).round()}%',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: removed
          ? BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
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
                  style: TextStyle(
                    color: removed ? _textMuted : _textDark,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    decoration: removed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                removed
                    ? 'غير محتسبة'
                    : (cost is num ? '$cost ريال' : 'لم يتم تسعيرها'),
                style: TextStyle(
                  color: removed
                      ? _textMuted
                      : (cost is num ? _textDark : Colors.red),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  decoration: removed ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          if (confidenceParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                confidenceParts.join(' • '),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _textMuted, fontSize: 11),
              ),
            ),
          if (flags.isNotEmpty && !removed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                flags.map((f) => _costFactorLabel(f.toString())).join('، '),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.red, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  // Independent, read-only row for the "جميع أضرار النموذج الأصلية" section —
  // always renders from original* fields, never from the item's current
  // (possibly edited/removed) state, so it stays a fixed record of what the
  // model actually detected regardless of anything the admin does to the
  // item elsewhere on this list.
  Widget _originalDetectionTile(Map<String, dynamic> item) {
    final String partKey = item['originalPart']?.toString() ?? '';
    final String damageKey = item['originalDamageType']?.toString() ?? '';
    final dynamic cost = item['originalLineCostSar'];

    final String partLabel =
        _partLabelAr[partKey] ?? (partKey.isEmpty ? 'غير محدد' : partKey);
    final String damageLabel =
        _damageTypeLabelAr[damageKey] ??
        (damageKey.isEmpty ? 'غير محدد' : damageKey);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
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
            cost is num ? '$cost ريال' : 'لم يتم تسعيرها',
            style: const TextStyle(
              color: _textDark,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 6: estimated cost total ──────────────────────────────────────
  //
  // displayCostSar/displayCostSource (cost rule v2 display switch, see
  // backend_api/services/cost_v2/spec/DECISION_cost_rule_v2.md §7-8) are what
  // this card shows; cases predating the switch have neither field, so this
  // falls back to the old estimatedCostSar field and renders exactly as
  // before. costV2Lines (when displayCostSource=='v2') is a CASE-level
  // breakdown already collapsed by panel across all images (cost_v2's
  // aggregation="one_panel") -- it is not image-scoped like the v1 costItems
  // list above, so it is shown once here rather than per image.

  Widget _costTotalCard(Map<String, dynamic> caseData) {
    final dynamic displayRaw = caseData['displayCostSar'];
    final dynamic totalRaw = displayRaw is num
        ? displayRaw
        : caseData['estimatedCostSar'];
    if (totalRaw is! num) {
      return const SizedBox.shrink();
    }
    final bool isV2 =
        displayRaw is num && caseData['displayCostSource'] == 'v2';
    final List<dynamic> v2Lines =
        isV2 ? ((caseData['costV2Lines'] as List?) ?? const []) : const [];
    final Map<String, dynamic> v2Config = isV2
        ? ((caseData['costV2Config'] as Map<String, dynamic>?) ?? const {})
        : const {};

    return _sectionCard(
      title: 'التكلفة التقديرية',
      subtitle: '$totalRaw ريال',
      children: [
        _infoBox('الإجمالي التقديري', '$totalRaw ريال'),
        if (isV2 && v2Lines.isNotEmpty) ...[
          _mutedCaption('تفصيل التكلفة'),
          ...v2Lines.map(
            (l) => _costV2LineTile(l as Map<String, dynamic>),
          ),
          _costV2Footer(v2Config),
        ],
      ],
    );
  }

  Widget _costV2LineTile(Map<String, dynamic> line) {
    final String partKey = _partFromPanelId(line['panel_id']?.toString());
    final String damageKey = line['damage']?.toString() ?? '';
    final String? severity = line['severity'] as String?;
    final dynamic hours = line['hours'];
    final dynamic factor = line['factor'];
    final dynamic cost = line['line_sar'];

    final String partLabel =
        _partLabelAr[partKey] ?? (partKey.isEmpty ? 'غير محدد' : partKey);
    final String damageLabel =
        _damageTypeLabelAr[damageKey] ??
        (damageKey.isEmpty ? 'غير محدد' : damageKey);

    final List<String> detailParts = [
      if (hours is num) 'الساعات: $hours',
      if (factor is num) 'عامل الشدة: $factor',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
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
              Row(
                children: [
                  _severityChip(severity),
                  const SizedBox(width: 6),
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
            ],
          ),
          if (detailParts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detailParts.join(' • '),
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _textMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _costV2Footer(Map<String, dynamic> config) {
    final dynamic rate = config['rate'];
    final String table = config['table']?.toString() ?? '—';
    final String version = config['rule_version']?.toString() ?? '—';
    final String rateText = rate is num ? '$rate' : '—';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        'عمالة فقط (هيكل وصبغ) — $rateText ريال/ساعة — جدول $table — نسخة $version',
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.right,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Section 7: admin review reasons ──────────────────────────────────────
  // No numeric confidence score or level here on purpose — an admin either
  // needs to look at this case or doesn't, and the only useful thing to show
  // is the plain-language reason list the backend already explains in
  // full sentences (see confidence_service.py / cost_estimation_services.py).

  Widget _confidenceDetailCard(Map<String, dynamic> caseData) {
    final bool requiresReview = caseData['needsAdminReview'] == true;
    final List<dynamic> reasons =
        (caseData['adminReviewReasonsAr'] as List?) ?? const [];

    return _sectionCard(
      title: 'مراجعة الإدارة',
      subtitle: requiresReview ? 'تحتاج إلى مراجعة' : 'لا تحتاج إلى مراجعة',
      needsAttention: requiresReview && reasons.isNotEmpty,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: requiresReview
                ? const Color(0xFFFFF7ED)
                : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  (requiresReview
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF16A34A))
                      .withOpacity(0.4),
            ),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                requiresReview
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: requiresReview
                    ? const Color(0xFFEA580C)
                    : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  requiresReview
                      ? 'تحتاج هذه الحالة إلى مراجعة إضافية من المشرف قبل اعتمادها'
                      : 'لا توجد أسباب تستدعي مراجعة إضافية من المشرف لهذه الحالة',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: requiresReview
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF15803D),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (requiresReview && reasons.isNotEmpty) ...[
          _mutedCaption('أسباب طلب المراجعة'),
          ...reasons.map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 5, color: _textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.toString(),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
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
            if (caseData['displayCostSar'] is num ||
                caseData['estimatedCostSar'] is num)
              const SizedBox(height: 16),
            _confidenceDetailCard(caseData),
          ],
        );
      },
    );
  }
}

/// The card shell every top-level section (`ملخص الطلب`, `التكلفة التقديرية`,
/// etc.) is built from. Collapsed by default so the reviewer sees the whole
/// case as a stack of one-line headers first — each header keeps a short
/// [subtitle] preview of that section's content (e.g. the status, the total
/// cost) so nothing important is hidden without a tap. Tapping the header
/// swaps the subtitle for the full [children] content, same as before.
class _CollapsibleCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool needsAttention;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _CollapsibleCard({
    required this.title,
    this.subtitle,
    this.needsAttention = false,
    required this.initiallyExpanded,
    required this.children,
  });

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final bool showSubtitle =
        !_expanded &&
        widget.subtitle != null &&
        widget.subtitle!.trim().isNotEmpty;

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
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: CaseAssessmentView._textDark,
                            ),
                          ),
                          if (widget.needsAttention) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.priority_high_rounded,
                              size: 18,
                              color: Color(0xFFEA580C),
                            ),
                          ],
                        ],
                      ),
                      if (showSubtitle) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle!,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: CaseAssessmentView._textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: CaseAssessmentView._textMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}
