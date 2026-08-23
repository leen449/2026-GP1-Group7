import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../NavBar/nav_bar.dart';

class EligibleObjectionCase {
  const EligibleObjectionCase({
    required this.caseId,
    this.reportId,
    required this.referenceDate,
    this.totalCost,
  });

  final String caseId;
  // Null when no report has been generated for this case yet — a case is
  // objectable as soon as it's reviewed, independent of report creation.
  final String? reportId;
  // The report's issued_at when a report exists, otherwise the case's own
  // createdAt — used for display and list ordering only.
  final DateTime referenceDate;
  // The report's total_cost_sar when a report exists, otherwise the case's
  // own (pre-report) estimatedCostSar if available.
  final num? totalCost;

  bool get hasReport => reportId != null;
}

class SubmitObjectionScreen extends StatefulWidget {
  const SubmitObjectionScreen({super.key});

  @override
  State<SubmitObjectionScreen> createState() => _SubmitObjectionScreenState();
}

class _SubmitObjectionScreenState extends State<SubmitObjectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _reasonController = TextEditingController();
  // List of cases eligible for objection
  List<EligibleObjectionCase> _eligibleCases = [];

  String? _selectedCaseId;

  bool _isLoading = true;
  bool _isSubmitting = false;

  static const Color primaryColor = Color(0xFF1E3A6E);
  static const Color darkTextColor = Color(0xFF111827);
  static const Color secondaryTextColor = Color(0xFF64748B);
  static const Color backgroundColor = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadEligibleCases();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // Loads all cases that are eligible for objection
  // Conditions:
  // Belongs to the current user
  // Case status is "تم المراجعة" (report can only be generated at this status)
  // A report exists
  // Report is within the 10-day objection period
  // No previous objection has been submitted
  Future<void> _loadEligibleCases() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get the currently authenticated user
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        throw Exception('يجب تسجيل الدخول أولًا.');
      }

      debugPrint('[objDebug] currentUser.uid = ${currentUser.uid}');

      // Some accidentCase documents save ownerId as the Firebase Auth UID,
      // others save it as the user's document id inside the users
      // collection (see the same workaround in history_screen.dart /
      // home_screen.dart). Collect both possible ids so cases created
      // through either code path are found.
      final Set<String> possibleOwnerIds = {currentUser.uid};

      final String? phoneNumber = currentUser.phoneNumber;

      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        final userQuery = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: phoneNumber)
            .limit(1)
            .get();

        if (userQuery.docs.isNotEmpty) {
          possibleOwnerIds.add(userQuery.docs.first.id);
        }
      }

      debugPrint('[objDebug] possibleOwnerIds = $possibleOwnerIds');

      // Retrieve all reviewed cases for the current user, across every
      // possible ownerId, then de-dup by document id.
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
      uniqueCaseDocuments = {};

      for (final ownerId in possibleOwnerIds) {
        final caseSnapshot = await _firestore
            .collection('accidentCase')
            .where('ownerId', isEqualTo: ownerId)
            .where('status', isEqualTo: 'تم المراجعة')
            .get();

        for (final document in caseSnapshot.docs) {
          uniqueCaseDocuments[document.id] = document;
        }
      }

      debugPrint(
        '[objDebug] cases matching possibleOwnerIds+status=تم المراجعة: '
        '${uniqueCaseDocuments.length}',
      );

      final List<EligibleObjectionCase> eligibleCases = [];

      // Loop through each case and validate its eligibility
      for (final caseDocument in uniqueCaseDocuments.values) {
        final caseData = caseDocument.data();

        final String caseId =
            (caseData['caseID'] as String?)?.trim().isNotEmpty == true
            ? caseData['caseID'] as String
            : caseDocument.id;

        debugPrint(
          '[objDebug] case doc=${caseDocument.id} caseId=$caseId '
          'rawStatus=${caseData['status']} reportId=${caseData['reportId']}',
        );

        // Check whether an objection already exists
        final existingObjection = await _firestore
            .collection('objection')
            .where('caseId', isEqualTo: caseId)
            .limit(1)
            .get();

        if (existingObjection.docs.isNotEmpty) {
          debugPrint('[objDebug] $caseId SKIP: objection already exists');
          continue;
        }

        // A case is objectable as soon as it's reviewed, whether or not a
        // report has been generated for it yet. The report is linked from
        // the case document (reportId) — report documents themselves have
        // no caseId field, so they must be fetched by id rather than
        // queried. When present, the 10-day objection window is measured
        // from the report's issued_at, matching the printed PDF notice;
        // when absent, there's nothing issued yet to start that clock, so
        // the case stays eligible.
        final String? reportId = (caseData['reportId'] as String?)?.trim();

        String? resolvedReportId;
        DateTime? issuedAt;
        num? totalCost;

        if (reportId != null && reportId.isNotEmpty) {
          final reportSnapshot = await _firestore
              .collection('reports')
              .doc(reportId)
              .get();

          if (reportSnapshot.exists) {
            final reportData = reportSnapshot.data() ?? {};

            // issued_at is stored as an ISO date string, not a Timestamp.
            final String? issuedAtValue = reportData['issued_at'] as String?;
            issuedAt = issuedAtValue != null
                ? DateTime.tryParse(issuedAtValue)
                : null;

            if (issuedAt != null) {
              final DateTime objectionDeadline = issuedAt.add(
                const Duration(days: 10),
              );

              if (DateTime.now().isAfter(objectionDeadline)) {
                debugPrint(
                  '[objDebug] $caseId SKIP: deadline passed '
                  '(issuedAt=$issuedAt)',
                );
                continue;
              }
            }

            final dynamic totalCostValue = reportData['total_cost_sar'];
            totalCost = totalCostValue is num ? totalCostValue : null;
            resolvedReportId = reportSnapshot.id;
          } else {
            debugPrint(
              '[objDebug] $caseId: report doc $reportId not found '
              '(or not readable) — treating as not-yet-generated',
            );
          }
        }

        final DateTime referenceDate =
            issuedAt ??
            (caseData['createdAt'] is Timestamp
                ? (caseData['createdAt'] as Timestamp).toDate()
                : DateTime.now());

        final num? estimatedCost =
            totalCost ??
            (caseData['estimatedCostSar'] is num
                ? caseData['estimatedCostSar'] as num
                : null);

        debugPrint(
          '[objDebug] $caseId ELIGIBLE (hasReport=${resolvedReportId != null})',
        );
        // Add the eligible case to the display list
        eligibleCases.add(
          EligibleObjectionCase(
            caseId: caseId,
            reportId: resolvedReportId,
            referenceDate: referenceDate,
            totalCost: estimatedCost,
          ),
        );
      }

      // Sort cases by the newest first
      eligibleCases.sort(
        (first, second) => second.referenceDate.compareTo(first.referenceDate),
      );

      if (!mounted) return;

      setState(() {
        _eligibleCases = eligibleCases;
        _isLoading = false;
      });
    } on FirebaseException catch (error) {
      debugPrint(
        '[objDebug] FirebaseException: ${error.code} ${error.message}',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        error.message ?? 'حدث خطأ أثناء تحميل الحالات.',
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  // Validates the input and submits a new objection to Firestore
  Future<void> _submitObjection() async {
    FocusScope.of(context).unfocus();

    final String reason = _reasonController.text.trim();

    if (_selectedCaseId == null) {
      _showMessage(
        'يرجى اختيار الحالة التي تريد الاعتراض عليها.',
        isError: true,
      );
      return;
    }

    if (reason.isEmpty) {
      _showMessage('يرجى كتابة سبب الاعتراض.', isError: true);
      return;
    }

    if (reason.length < 10) {
      _showMessage('يرجى توضيح سبب الاعتراض بشكل أكبر.', isError: true);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final existingObjection = await _firestore
          .collection('objection')
          .where('caseId', isEqualTo: _selectedCaseId)
          .limit(1)
          .get();

      if (existingObjection.docs.isNotEmpty) {
        throw Exception('سبق تقديم اعتراض على هذه الحالة.');
      }

      final caseQuery = await _firestore
          .collection('accidentCase')
          .where('caseID', isEqualTo: _selectedCaseId)
          .limit(1)
          .get();

      DocumentSnapshot<Map<String, dynamic>>? caseDocument;

      if (caseQuery.docs.isNotEmpty) {
        caseDocument = caseQuery.docs.first;
      } else {
        final directDocument = await _firestore
            .collection('accidentCase')
            .doc(_selectedCaseId)
            .get();

        if (directDocument.exists) {
          caseDocument = directDocument;
        }
      }

      if (caseDocument == null || !caseDocument.exists) {
        throw Exception('لم يتم العثور على الحالة المحددة.');
      }

      final caseData = caseDocument.data();

      if (caseData?['status'] != 'تم المراجعة') {
        throw Exception('لا يمكن تقديم اعتراض لأن حالة الكيس تغيرت.');
      }

      // A case is objectable as soon as it's reviewed, whether or not a
      // report has been generated for it yet. The report is linked from
      // the case document (reportId) — report documents themselves have
      // no caseId field, so they must be fetched by id rather than
      // queried. When there's no report yet, there's nothing to flag under
      // claim review and no 10-day clock has started, so we just skip
      // straight to creating the objection.
      final String? reportId = (caseData?['reportId'] as String?)?.trim();

      DocumentSnapshot<Map<String, dynamic>>? reportSnapshot;

      if (reportId != null && reportId.isNotEmpty) {
        final snapshot = await _firestore
            .collection('reports')
            .doc(reportId)
            .get();

        if (snapshot.exists) {
          final reportData = snapshot.data() ?? {};

          // issued_at is stored as an ISO date string, not a Timestamp.
          final String? issuedAtValue = reportData['issued_at'] as String?;
          final DateTime? issuedAt = issuedAtValue != null
              ? DateTime.tryParse(issuedAtValue)
              : null;

          if (issuedAt != null) {
            final DateTime deadline = issuedAt.add(const Duration(days: 10));

            if (DateTime.now().isAfter(deadline)) {
              throw Exception(
                'انتهت المدة المحددة لتقديم اعتراض على هذه الحالة.',
              );
            }
          }

          reportSnapshot = snapshot;
        }
      }

      final objectionReference = _firestore.collection('objection').doc();

      // Mark the report under claim review atomically with creating the
      // objection, so one is never written without the other. `status` is
      // explicitly excluded from the report's signed facts (see
      // _canonical_facts in report_verification_service.py), so this plain
      // field update doesn't invalidate the signature. Skipped entirely
      // when no report exists yet — there's nothing to flag.
      final batch = _firestore.batch();

      batch.set(objectionReference, {
        'caseId': _selectedCaseId,
        'reason': reason,
        'objectionStatus': 'قيد المراجعة',
        'adminFeedback': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (reportSnapshot != null) {
        batch.update(reportSnapshot.reference, {'status': 'claim_pending'});
      }

      await batch.commit();

      if (!mounted) return;

      _showSuccessDialog();

      // Remove the submitted case from the eligible list
      setState(() {
        _eligibleCases.removeWhere((item) => item.caseId == _selectedCaseId);

        _selectedCaseId = null;
        _reasonController.clear();
        _isSubmitting = false;
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(error.message ?? 'تعذر تقديم الاعتراض.', isError: true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.right),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 42),
                ),

                const SizedBox(height: 20),

                const Text(
                  'تم تقديم الاعتراض بنجاح',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: darkTextColor,
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Close the success dialog.
                      Navigator.of(dialogContext).pop();

                      // Go to the home page
                      Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AppBottomNav()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: const Text(
                      'حسنًا',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: const Text(
            'تقديم اعتراض',
            style: TextStyle(
              color: darkTextColor,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadEligibleCases,
            color: primaryColor,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).size.height * 0.14,
      ),
      children: [
        const Text(
          'اختر الحالة التي ترغب في الاعتراض عليها، ثم وضّح سبب اعتراضك.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),

        _buildSectionHeader(
          icon: Icons.description_outlined,
          title: 'اختر الحالة',
          subtitle: 'تظهر فقط الحالات التي يمكنك تقديم اعتراض عليها.',
        ),

        const SizedBox(height: 14),

        if (_eligibleCases.isEmpty)
          _buildEmptyState()
        else if (_eligibleCases.length <= 2)
          ..._eligibleCases.map(_buildCaseCard)
        else
          SizedBox(
            height: 450, // مساحة تعرض تقريبًا بطاقتين
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _eligibleCases.length,
                itemBuilder: (context, index) {
                  return _buildCaseCard(_eligibleCases[index]);
                },
              ),
            ),
          ),

        const SizedBox(height: 28),

        _buildReasonSection(),

        const SizedBox(height: 22),

        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitObjection,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: primaryColor,
              disabledBackgroundColor: const Color(0xFF93C5FD),
              foregroundColor: Colors.white,
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
                : const Text(
                    'تقديم الاعتراض',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: primaryColor, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: secondaryTextColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Builds a selectable card displaying the case information
  Widget _buildCaseCard(EligibleObjectionCase item) {
    final bool isSelected = _selectedCaseId == item.caseId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              _selectedCaseId = item.caseId;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
                width: isSelected ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Radio<String>(
                      value: item.caseId,
                      groupValue: _selectedCaseId,
                      activeColor: primaryColor,
                      onChanged: (value) {
                        setState(() {
                          _selectedCaseId = value;
                        });
                      },
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF16A34A),
                            size: 17,
                          ),
                          SizedBox(width: 5),
                          Text(
                            // Every case in this list was fetched with
                            // status == 'تم المراجعة' (see _loadEligibleCases),
                            // so that's its real, current status — not the
                            // unrelated 'تم الفحص' stage.
                            'تم المراجعة',
                            style: TextStyle(
                              color: Color(0xFF15803D),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),

                _buildCardMainValue(
                  label: 'رقم الحالة',
                  value: item.caseId,
                  icon: Icons.folder_copy_outlined,
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                ),

                Row(
                  children: [
                    Expanded(
                      child: _buildCardDetail(
                        icon: Icons.calendar_month_outlined,
                        label: item.hasReport
                            ? 'تاريخ إصدار التقرير'
                            : 'تاريخ المراجعة',
                        value:
                            '${item.referenceDate.day}/${item.referenceDate.month}/${item.referenceDate.year}',
                      ),
                    ),
                    Container(
                      height: 52,
                      width: 1,
                      color: const Color(0xFFE2E8F0),
                    ),
                    Expanded(
                      child: _buildCardDetail(
                        icon: Icons.payments_outlined,
                        label: item.hasReport
                            ? 'إجمالي المبلغ'
                            : 'التكلفة التقديرية',
                        value: item.totalCost != null
                            ? '${item.totalCost} ريال'
                            : 'غير متاحة بعد',
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
  }

  Widget _buildCardMainValue({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: primaryColor),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: darkTextColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardDetail({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: primaryColor, size: 21),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: darkTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // Builds the objection reason input section
  Widget _buildReasonSection() {
    return Column(
      children: [
        _buildSectionHeader(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'سبب الاعتراض',
          subtitle: '',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _reasonController,
          maxLength: 1000,
          minLines: 5,
          maxLines: 7,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'اكتب سبب اعتراضك هنا...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: primaryColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // Displays a message when no eligible cases are available
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 35),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.inbox_outlined, size: 52, color: Color(0xFF94A3B8)),
          SizedBox(height: 14),
          Text(
            'لا توجد حالات متاحة للاعتراض',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkTextColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'قد تكون مدة الاعتراض قد انتهت أو تم تقديم اعتراض مسبقًا.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
