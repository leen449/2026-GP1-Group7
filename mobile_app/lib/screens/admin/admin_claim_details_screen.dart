import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_navigation.dart';
import 'widgets/case_assessment_view.dart';

/// Admin-facing claim (objection) review screen. Reuses the same
/// [CaseAssessmentView] the Case Review screen uses for the underlying
/// case/model-assessment content, plus the objection's own reason and the
/// accept/reject actions — no separate/duplicate assessment UI.
class AdminClaimDetailsScreen extends StatefulWidget {
  final String objectionId;

  const AdminClaimDetailsScreen({super.key, required this.objectionId});

  @override
  State<AdminClaimDetailsScreen> createState() => _AdminClaimDetailsScreenState();
}

class _AdminClaimDetailsScreenState extends State<AdminClaimDetailsScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF1E3A6E);

  bool _isSubmitting = false;

  /// Same dual lookup submit_objection_screen.dart uses when resolving an
  /// objection's caseId field: some case docs carry a human-readable
  /// `caseID` field distinct from the Firestore document id, some don't.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveAccidentCaseDoc(String rawCaseId) async {
    final byField = await FirebaseFirestore.instance
        .collection('accidentCase')
        .where('caseID', isEqualTo: rawCaseId)
        .limit(1)
        .get();

    if (byField.docs.isNotEmpty) {
      return byField.docs.first;
    }

    final byId = await FirebaseFirestore.instance.collection('accidentCase').doc(rawCaseId).get();
    return byId.exists ? byId : null;
  }

  void _showMessage(String message, {required bool isError}) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: Transform.translate(
                offset: const Offset(0, -3),
                child: Text(
                  message,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(height: 1.0),
                ),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            top: topPadding + kToolbarHeight + 35,
            left: 16,
            right: 16,
            bottom: screenHeight - topPadding - kToolbarHeight - 70,
          ),
          duration: const Duration(seconds: 3),
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
          BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textDark),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow({required String title, required String value, bool ltr = false}) {
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
          Text(title, textDirection: TextDirection.rtl, style: const TextStyle(color: _textMuted, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value.trim().isEmpty ? '—' : value,
                textAlign: TextAlign.right,
                style: const TextStyle(color: _textDark, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<bool> _confirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(screenWidth * 0.06),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Icon(icon, color: iconColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 17),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEDEDED),
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 0,
                            ),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              elevation: 4,
                            ),
                            child: Text(confirmLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return result == true;
  }

  /// Reason-entry dialog for rejection — same multiline TextField style as
  /// submit_objection_screen.dart's objection-reason field.
  Future<String?> _rejectReasonDialog() async {
    final controller = TextEditingController();
    String? error;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final screenWidth = MediaQuery.of(ctx).size.width;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screenWidth > 600 ? 420 : screenWidth * 0.9),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(screenWidth * 0.06),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            const Icon(Icons.gpp_bad_outlined, color: Colors.red),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'رفض الاعتراض',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 17),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: controller,
                          maxLength: 1000,
                          minLines: 3,
                          maxLines: 6,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            hintText: 'اكتب سبب رفض الاعتراض هنا...',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: error != null ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1),
                                width: error != null ? 1.5 : 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: error != null ? const Color(0xFFDC2626) : _primaryBlue,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              error!,
                              textAlign: TextAlign.right,
                              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEDEDED),
                                  foregroundColor: Colors.black87,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  elevation: 0,
                                ),
                                child: const Text('إلغاء'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final text = controller.text.trim();
                                  if (text.isEmpty) {
                                    setDialogState(() => error = 'يرجى كتابة سبب الرفض.');
                                    return;
                                  }
                                  Navigator.pop(ctx, text);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  elevation: 4,
                                ),
                                child: const Text('تأكيد الرفض'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleReject() async {
    if (_isSubmitting) return;
    final reason = await _rejectReasonDialog();
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance.collection('objection').doc(widget.objectionId).update({
        'objectionStatus': 'تم رفض الاعتراض',
        'adminFeedback': reason.trim(),
      });
      if (!mounted) return;
      _showMessage('تم رفض الاعتراض', isError: false);
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleAccept(String resolvedCaseId) async {
    if (_isSubmitting) return;
    final confirmed = await _confirmDialog(
      icon: Icons.check_circle_outline_rounded,
      iconColor: _primaryBlue,
      title: 'قبول الاعتراض؟',
      body: 'سيتم قبول الاعتراض وإعادة فتح الحالة لتعديل التقييم.',
      confirmLabel: 'قبول الاعتراض',
    );
    if (!confirmed) return;

    setState(() => _isSubmitting = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('objection').doc(widget.objectionId), {
        'objectionStatus': 'تم اعتماد الاعتراض',
      });
      batch.update(FirebaseFirestore.instance.collection('accidentCase').doc(resolvedCaseId), {
        'status': 'تم حساب التكلفة',
      });
      await batch.commit();

      if (!mounted) return;
      _showMessage('تم قبول الاعتراض', isError: false);
      await AdminNavigation.openAddDamage(context, resolvedCaseId);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _actionButtons(String resolvedCaseId) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleReject,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFFEDEDED),
                disabledBackgroundColor: const Color(0xFFEDEDED),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text(
                'رفض الاعتراض',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : () => _handleAccept(resolvedCaseId),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: _primaryBlue,
                disabledBackgroundColor: const Color(0xFF93C5FD),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'قبول الاعتراض',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ],
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios_rounded, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'مراجعة الاعتراض',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('objection').doc(widget.objectionId).snapshots(),
        builder: (context, objSnap) {
          if (objSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!objSnap.hasData || !objSnap.data!.exists) {
            return const Center(
              child: Text(
                'لم يتم العثور على الاعتراض',
                textDirection: TextDirection.rtl,
                style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
              ),
            );
          }

          final data = objSnap.data!.data() ?? {};
          final rawCaseId = data['caseId']?.toString() ?? '';
          final reason = data['reason']?.toString() ?? '';
          final status = data['objectionStatus']?.toString() ?? 'قيد المراجعة';
          final createdAt = data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null;

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
            future: _resolveAccidentCaseDoc(rawCaseId),
            builder: (context, caseSnap) {
              if (caseSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final resolvedDoc = caseSnap.data;
              if (resolvedDoc == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'لم يتم العثور على الحالة المرتبطة بهذا الاعتراض ($rawCaseId)',
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }

              final resolvedCaseId = resolvedDoc.id;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _sectionCard(
                      title: 'معلومات الاعتراض',
                      children: [
                        _infoRow(title: 'رقم الاعتراض', value: widget.objectionId, ltr: true),
                        _infoRow(title: 'رقم الحالة', value: rawCaseId, ltr: true),
                        _infoRow(title: 'تاريخ التقديم', value: _formatDate(createdAt)),
                        _infoRow(title: 'حالة الاعتراض (داخلية)', value: status),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      title: 'وصف الاعتراض',
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _pageBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8EEF7)),
                          ),
                          child: Text(
                            reason.trim().isEmpty ? 'لا يوجد وصف للاعتراض' : reason,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: _textDark, fontSize: 14, fontWeight: FontWeight.w600, height: 1.7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CaseAssessmentView(caseId: resolvedCaseId),
                    const SizedBox(height: 20),
                    _actionButtons(resolvedCaseId),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
