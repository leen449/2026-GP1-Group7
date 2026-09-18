import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../widgets/case_assessment_view.dart';
import '../edits/edit_damages_screen.dart';

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
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF1E3A6E);
  // Matches رفض الاعتراض's exact style in admin_claim_details_screen.dart:
  // light grey fill + dark text, not a filled/vivid color — this is not a
  // rejection, but visually it should read as the app's "secondary action"
  // button, same family as إلغاء/رفض, rather than a primary filled color.
  static const Color _referColor = Color(0xFFEDEDED);
  static const Color _referTextColor = Colors.black87;
  static const Color _referIconColor = Color(0xFF64748B);

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

  /// Combined confirm + reason-selection dialog for referring a case to the
  /// specialist. `systemReasons` are the case's already-computed
  /// `adminReviewReasonsAr` (vehicle age, missing market value, ...) shown as
  /// toggleable rows so the admin picks from what the system already flagged
  /// instead of typing everything freehand; an optional free-text field
  /// covers anything not already covered. Returns the combined reason list
  /// (selected system reasons, in order, plus the free text if any), or null
  /// if cancelled. Same responsive Dialog/ConstrainedBox shell as
  /// _confirmDialog — never a bare AlertDialog with an unconstrained Row.
  Future<List<String>?> _referReasonDialog(List<String> systemReasons) async {
    final controller = TextEditingController();
    final Set<String> selectedReasons = {};
    String? error;

    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final screenWidth = MediaQuery.of(ctx).size.width;
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screenWidth > 600 ? 420 : screenWidth * 0.9,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(screenWidth * 0.06),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Icon(
                              Icons.person_search_rounded,
                              color: _referIconColor,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'إحالة إلى شيخ المعارض؟',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: _textDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'سيتم إحالة هذه الحالة إلى شيخ المعارض لتقييم '
                          'القيمة السوقية للمركبة بدلاً من تقدير تكلفة '
                          'الإصلاح. اختر سبب الإحالة الذي سيظهر للعميل:',
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        if (systemReasons.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'الأسباب المقترحة',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: _textMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...systemReasons.map((reason) {
                            final bool isSelected = selectedReasons.contains(
                              reason,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setDialogState(() {
                                  if (isSelected) {
                                    selectedReasons.remove(reason);
                                  } else {
                                    selectedReasons.add(reason);
                                  }
                                  error = null;
                                }),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFEAF1FF)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? _primaryBlue
                                          : const Color(0xFFCBD5E1),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    textDirection: TextDirection.rtl,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        size: 20,
                                        color: isSelected
                                            ? _primaryBlue
                                            : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          reason,
                                          textDirection: TextDirection.rtl,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: _textDark,
                                            fontSize: 13.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            height: 1.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            systemReasons.isEmpty
                                ? 'سبب الإحالة'
                                : 'سبب إضافي (اختياري)',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              color: _textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: controller,
                          maxLength: 500,
                          minLines: 2,
                          maxLines: 4,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          onChanged: (_) =>
                              setDialogState(() => error = null),
                          decoration: InputDecoration(
                            hintText: systemReasons.isEmpty
                                ? 'اكتب سبب الإحالة هنا...'
                                : 'أضف سببًا إضافيًا (اختياري)...',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.all(16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: error != null
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFFCBD5E1),
                                width: error != null ? 1.5 : 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: error != null
                                    ? const Color(0xFFDC2626)
                                    : _primaryBlue,
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
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx),
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
                                  onPressed: () {
                                    final freeText = controller.text.trim();
                                    if (selectedReasons.isEmpty &&
                                        freeText.isEmpty) {
                                      setDialogState(
                                        () => error =
                                            'يرجى اختيار سبب واحد على الأقل '
                                            'أو كتابة سبب الإحالة.',
                                      );
                                      return;
                                    }
                                    Navigator.pop(ctx, <String>[
                                      ...systemReasons.where(
                                        selectedReasons.contains,
                                      ),
                                      if (freeText.isNotEmpty) freeText,
                                    ]);
                                  },
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
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('تأكيد الإحالة'),
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
      },
    );
  }

  Future<void> _writeStatus(
    String status, {
    required String successMessage,
    Map<String, dynamic> extraFields = const {},
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .update({'status': status, ...extraFields});
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
    List<String> systemReasons = const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .get();
      systemReasons =
          ((snap.data()?['adminReviewReasonsAr'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
    } catch (_) {
      // Fetch failure just falls back to an empty list; the dialog still
      // lets the admin type a reason freehand.
    }
    if (!mounted) return;

    final reasons = await _referReasonDialog(systemReasons);
    if (reasons == null || reasons.isEmpty) return;

    await _writeStatus(
      _referredStatus,
      successMessage: 'تم إحالة الحالة لشيخ المعارض',
      extraFields: {
        'referralReasonsAr': reasons,
        'referredAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Widget _actionButton({
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
    Color foregroundColor = Colors.white,
    Color disabledBackgroundColor = const Color(0xFF93C5FD),
    Color spinnerColor = Colors.white,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          disabledBackgroundColor: disabledBackgroundColor,
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: spinnerColor,
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
        padding: EdgeInsets.fromLTRB(18, 14, 18, bottomPad + 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CaseAssessmentView(
              caseId: widget.caseId,
              onEditImage: (imageId, imageUrl, imageNumber) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditDamagesScreen(
                      caseId: widget.caseId,
                      imageId: imageId,
                      imageUrl: imageUrl,
                      imageNumber: imageNumber,
                    ),
                  ),
                );
              },
            ),
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
                    foregroundColor: _referTextColor,
                    disabledBackgroundColor: _referColor,
                    spinnerColor: _referTextColor,
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
