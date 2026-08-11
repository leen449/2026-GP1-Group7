import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ObjectionDetailsScreen extends StatelessWidget {
  final String objectionId;

  const ObjectionDetailsScreen({
    super.key,
    required this.objectionId,
  });

  // نفس ألوان الـ Home بالضبط
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          surfaceTintColor: _pageBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,

          // نفس اتجاه سهم الصفحات الحالية
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _textDark,
              size: 20,
            ),
          ),

          title: const Text(
            'تفاصيل الاعتراض',
            style: TextStyle(
              color: _textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('objection')
              .doc(objectionId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: _primaryBlue,
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'تعذر تحميل تفاصيل الاعتراض',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  'لم يتم العثور على الاعتراض',
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }

            final data = snapshot.data!.data() ?? {};

            final caseId = data['caseId']?.toString() ?? '';
            final reason = data['reason']?.toString() ?? '';
            final status =
                data['objectionStatus']?.toString() ?? 'قيد المراجعة';
            final adminFeedback =
                data['adminFeedback']?.toString().trim() ?? '';

            final createdAt = data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate()
                : null;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // معلومات الاعتراض
                  _sectionCard(
                    title: 'معلومات الاعتراض',
                    children: [
                      _infoRow(
                        title: 'رقم الاعتراض',
                        value: objectionId,
                        icon: Icons.description_outlined,
                        ltr: true,
                      ),
                      const SizedBox(height: 10),
                      _infoRow(
                        title: 'رقم الحالة',
                        value: caseId,
                        icon: Icons.folder_copy_outlined,
                        ltr: true,
                      ),
                      const SizedBox(height: 10),
                      _infoRow(
                        title: 'تاريخ التقديم',
                        value: _formatDate(createdAt),
                        icon: Icons.calendar_month_outlined,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _statusBadge(status),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // وصف / سبب الاعتراض
                  _sectionCard(
                    title: 'وصف الاعتراض',
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _pageBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE8EEF7),
                          ),
                        ),
                        child: Text(
                          reason.trim().isEmpty
                              ? 'لا يوجد وصف للاعتراض'
                              : reason,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: _textDark,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // رد الإدارة
                  _sectionCard(
                    title: 'رد الإدارة',
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: adminFeedback.isEmpty
                              ? const Color(0xFFF7FAFF)
                              : const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE8EEF7),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              adminFeedback.isEmpty
                                  ? Icons.schedule_rounded
                                  : Icons.admin_panel_settings_outlined,
                              color: adminFeedback.isEmpty
                                  ? _textMuted
                                  : _primaryBlue,
                              size: 21,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
child: Text(
                                adminFeedback.isEmpty
                                    ? 'لم يتم الرد على الاعتراض بعد'
                                    : adminFeedback,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: adminFeedback.isEmpty
                                      ? _textMuted
                                      : _textDark,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE8EEF7),
        ),
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
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow({
    required String title,
    required String value,
    required IconData icon,
    bool ltr = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: _pageBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE8EEF7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: _primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Directionality(
                  textDirection:
                      ltr ? TextDirection.ltr : TextDirection.rtl,
                  child: Text(
                    value.trim().isEmpty ? '—' : value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final s = status.trim();

    String displayStatus;
    Color bgColor;
    Color textColor;
    IconData icon;
if (s == 'قيد المراجعة' || s == 'pending') {
      displayStatus = 'قيد المراجعة';
      bgColor = const Color(0xFFEAF1FF);
      textColor = const Color(0xFF2563EB);
      icon = Icons.hourglass_empty_rounded;
    } else if (s == 'مرفوض' ||
        s == 'مرفوضة' ||
        s == 'rejected') {
      displayStatus = 'مرفوض';
      bgColor = const Color(0xFFFFEEF0);
      textColor = Colors.red;
      icon = Icons.gpp_bad_outlined;
    } else {
      displayStatus = s.isEmpty ? 'تمت المعالجة' : s;
      bgColor = const Color(0xFFDCFCE7);
      textColor = Colors.green;
      icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: textColor,
          ),
          const SizedBox(width: 5),
          Text(
            displayStatus,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'غير محدد';

    return '${date.day}/${date.month}/${date.year}';
  }
}