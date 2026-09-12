import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_navigation.dart';
import 'widgets/case_assessment_view.dart';

/// Admin-facing review screen for one accident case. Read-only assessment
/// content is delegated to [CaseAssessmentView] (shared with the Claim
/// Details screen); this screen only adds the edit entry point and the two
/// case-level review actions.
class AdminCaseReviewScreen extends StatefulWidget {
  final String caseId;

  const AdminCaseReviewScreen({super.key, required this.caseId});

  @override
  State<AdminCaseReviewScreen> createState() => _AdminCaseReviewScreenState();
}

class _AdminCaseReviewScreenState extends State<AdminCaseReviewScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _primaryBlue = Color(0xFF1E3A6E);
  static const Color _referColor = Color(0xFFDC2626);

  static const String _referredStatus = 'محالة لشيخ المعارض';

  bool _isSubmitting = false;

  // ── Flash message (copied verbatim from submit_objection_screen.dart) ────
  void _showMessage(String message, {required bool isError}) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: SizedBox(
            width: double.infinity,
            child: Text(
              message,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
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

  // ── Confirm dialog (copied pattern from vehicle_details_screen.dart) ─────
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
            ),
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
                            style: const TextStyle(
                              color: _textDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEDEDED),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 0,
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('إلغاء'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 4,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(confirmLabel),
                              ),
                            ),
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

  Future<void> _writeStatus(
    String status, {
    required String successMessage,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .update({'status': status});
      if (!mounted) return;
      _showMessage(successMessage, isError: false);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleApprove() async {
    final confirmed = await _confirmDialog(
      icon: Icons.check_circle_outline_rounded,
      iconColor: _primaryBlue,
      title: 'تأكيد الحالة؟',
      body: 'هل أنت متأكد من اعتماد نتائج تقييم هذه الحالة؟',
      confirmLabel: 'تاكيد الحالة',
    );
    if (!confirmed) return;
    await _writeStatus(
      'تمت المراجعة',
      successMessage: 'تم اعتماد الحالة بنجاح',
    );
  }

  Future<void> _handleReferToSpecialist() async {
    final confirmed = await _confirmDialog(
      icon: Icons.person_search_rounded,
      iconColor: _referColor,
      title: 'إحالة إلى شيخ المعارض؟',
      body:
          'سيتم إحالة هذه الحالة إلى شيخ المعارض لتقييم القيمة السوقية للمركبة بدلاً من تقدير تكلفة الإصلاح.',
      confirmLabel: 'تأكيد الإحالة',
    );
    if (!confirmed) return;
    await _writeStatus(
      _referredStatus,
      successMessage: 'تم إحالة الحالة لشيخ المعارض',
    );
  }

  Widget _actionButton({
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          disabledBackgroundColor: const Color(0xFF93C5FD),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
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
        leading: IconButton(
          icon: const Icon(Icons.edit_outlined, color: _textDark),
          tooltip: 'تعديل التقييم',
          onPressed: () =>
              AdminNavigation.openAddDamage(context, widget.caseId),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, color: _textDark),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text(
          'مراجعة الحالة',
          style: TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CaseAssessmentView(caseId: widget.caseId),
            const SizedBox(height: 20),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: _actionButton(
                    label: 'تاكيد الحالة',
                    backgroundColor: _primaryBlue,
                    onPressed: _handleApprove,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    label: 'إحالة لشيخ المعارض',
                    backgroundColor: _referColor,
                    onPressed: _handleReferToSpecialist,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
