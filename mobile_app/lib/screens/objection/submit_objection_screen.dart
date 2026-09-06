import 'dart:async';

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
  final String? reportId;
  final DateTime referenceDate;
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

  List<EligibleObjectionCase> _eligibleCases = [];

  String? _selectedCaseId;

  bool _isLoading = true;
  bool _isSubmitting = false;

  String? _reasonError;

  // Real-time listeners
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _casesSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _objectionsSubscription;

  static const Color primaryColor = Color(0xFF1E3A6E);
  static const Color darkTextColor = Color(0xFF111827);
  static const Color secondaryTextColor = Color(0xFF64748B);
  static const Color backgroundColor = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();

    // Load cases when the page opens
    _loadEligibleCases();

    // Automatically refresh when accident cases change
    _casesSubscription = _firestore
        .collection('accidentCase')
        .snapshots()
        .listen((_) {
          if (mounted) {
            _loadEligibleCases();
          }
        });

    // Automatically refresh when objections change
    _objectionsSubscription = _firestore
        .collection('objection')
        .snapshots()
        .listen((_) {
          if (mounted) {
            _loadEligibleCases();
          }
        });
  }

  @override
  void dispose() {
    _casesSubscription?.cancel();
    _objectionsSubscription?.cancel();

    _reasonController.dispose();

    super.dispose();
  }

  Future<void> _loadEligibleCases() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        throw Exception('يجب تسجيل الدخول أولًا.');
      }

      debugPrint('[objDebug] currentUser.uid = ${currentUser.uid}');

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

      for (final caseDocument in uniqueCaseDocuments.values) {
        final caseData = caseDocument.data();

        final String caseId =
            (caseData['caseID'] as String?)?.trim().isNotEmpty == true
            ? caseData['caseID'] as String
            : caseDocument.id;

        debugPrint(
          '[objDebug] case doc=${caseDocument.id} '
          'caseId=$caseId '
          'rawStatus=${caseData['status']} '
          'reportId=${caseData['reportId']}',
        );

        final existingObjection = await _firestore
            .collection('objection')
            .where('caseId', isEqualTo: caseId)
            .limit(1)
            .get();

        if (existingObjection.docs.isNotEmpty) {
          debugPrint('[objDebug] $caseId SKIP: objection already exists');

          continue;
        }

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
          '[objDebug] $caseId ELIGIBLE '
          '(hasReport=${resolvedReportId != null})',
        );

        eligibleCases.add(
          EligibleObjectionCase(
            caseId: caseId,
            reportId: resolvedReportId,
            referenceDate: referenceDate,
            totalCost: estimatedCost,
          ),
        );
      }

      eligibleCases.sort(
        (first, second) => second.referenceDate.compareTo(first.referenceDate),
      );

      if (!mounted) return;

      setState(() {
        _eligibleCases = eligibleCases;
        _isLoading = false;

        // If the currently selected case is no longer eligible,
        // remove the selection automatically.
        if (_selectedCaseId != null &&
            !_eligibleCases.any((item) => item.caseId == _selectedCaseId)) {
          _selectedCaseId = null;
        }
      });
    } on FirebaseException catch (error) {
      debugPrint(
        '[objDebug] FirebaseException: '
        '${error.code} ${error.message}',
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
      setState(() {
        _reasonError = 'يرجى كتابة سبب الاعتراض.';
      });

      return;
    }

    if (reason.length < 10) {
      setState(() {
        _reasonError = 'يرجى توضيح سبب الاعتراض بشكل أوضح.';
      });

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

      final String? reportId = (caseData?['reportId'] as String?)?.trim();

      DocumentSnapshot<Map<String, dynamic>>? reportSnapshot;

      if (reportId != null && reportId.isNotEmpty) {
        final snapshot = await _firestore
            .collection('reports')
            .doc(reportId)
            .get();

        if (snapshot.exists) {
          final reportData = snapshot.data() ?? {};

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

      setState(() {
        _eligibleCases.removeWhere((item) => item.caseId == _selectedCaseId);

        _selectedCaseId = null;
        _reasonController.clear();
        _reasonError = null;
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
                      Navigator.of(dialogContext).pop();

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

        // No RefreshIndicator.
        // Updates now happen automatically through Firestore listeners.
        body: SafeArea(child: _buildBody()),
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
        else
          _buildCasePickerField(),

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

  Widget _buildCaseCard(EligibleObjectionCase item) {
    final bool isSelected = _selectedCaseId == item.caseId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _selectedCaseId = item.caseId;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF5F9FF) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
                width: isSelected ? 1.8 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Transform.scale(
                      scale: 1.15,
                      child: Radio<String>(
                        value: item.caseId,
                        groupValue: _selectedCaseId,
                        activeColor: primaryColor,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (value) {
                          setState(() {
                            _selectedCaseId = value;
                          });
                        },
                      ),
                    ),

                    const Spacer(),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF3),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            color: Color(0xFF16A34A),
                            size: 16,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'تم المراجعة',
                            style: TextStyle(
                              color: Color(0xFF15803D),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 7),

                _buildCardMainValue(
                  label: 'رقم الحالة',
                  value: item.caseId,
                  icon: Icons.folder_copy_outlined,
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
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
                      height: 42,
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

  Widget _buildCasePickerField() {
    EligibleObjectionCase? selectedCase;

    if (_selectedCaseId != null) {
      for (final item in _eligibleCases) {
        if (item.caseId == _selectedCaseId) {
          selectedCase = item;
          break;
        }
      }
    }

    return InkWell(
      onTap: _showCasePicker,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _selectedCaseId != null
                ? primaryColor
                : const Color(0xFFCBD5E1),
            width: _selectedCaseId != null ? 1.5 : 1,
          ),
        ),
        child: selectedCase == null
            ? const Row(
                children: [
                  Expanded(
                    child: Text(
                      'اختر الحالة',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            selectedCase.caseId,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: darkTextColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${selectedCase.referenceDate.day}/'
                          '${selectedCase.referenceDate.month}/'
                          '${selectedCase.referenceDate.year}'
                          '${selectedCase.totalCost != null ? '  •  ${selectedCase.totalCost} ريال' : ''}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: primaryColor,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _showCasePicker() async {
    String? tempSelectedCaseId = _selectedCaseId;

    final confirmedCaseId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.78,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Bottom sheet handle
                        Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),

                        const SizedBox(height: 18),

                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'اختر الحالة',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: darkTextColor,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),

                            IconButton(
                              onPressed: () {
                                Navigator.pop(bottomSheetContext);
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: darkTextColor,
                                size: 27,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            itemCount: _eligibleCases.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _eligibleCases[index];

                              final bool isSelected =
                                  tempSelectedCaseId == item.caseId;

                              return _buildCasePickerItem(
                                item: item,
                                isSelected: isSelected,
                                onTap: () {
                                  setModalState(() {
                                    tempSelectedCaseId = item.caseId;
                                  });
                                },
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 18),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: tempSelectedCaseId == null
                                ? null
                                : () {
                                    Navigator.pop(
                                      bottomSheetContext,
                                      tempSelectedCaseId,
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: primaryColor,
                              disabledBackgroundColor: const Color(0xFFCBD5E1),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'تأكيد الاختيار',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (confirmedCaseId == null || !mounted) {
      return;
    }

    setState(() {
      _selectedCaseId = confirmedCaseId;
    });
  }

  Widget _buildCasePickerItem({
    required EligibleObjectionCase item,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFF5F9FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? primaryColor : const Color(0xFFE2E8F0),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Radio button stays on the right for the Arabic RTL layout.
              Radio<String>(
                value: item.caseId,
                groupValue: isSelected ? item.caseId : null,
                activeColor: primaryColor,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => onTap(),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              item.caseId,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: darkTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'تم المراجعة',
                            style: TextStyle(
                              color: Color(0xFF15803D),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_outlined,
                          size: 17,
                          color: secondaryTextColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${item.referenceDate.day}/'
                          '${item.referenceDate.month}/'
                          '${item.referenceDate.year}',
                          style: const TextStyle(
                            color: secondaryTextColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    if (item.totalCost != null) ...[
                      const SizedBox(height: 7),

                      Row(
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 17,
                            color: secondaryTextColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${item.totalCost} ريال',
                            style: const TextStyle(
                              color: darkTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'سبب الاعتراض',
          subtitle: '',
        ),

        if (_reasonError != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 54),
            child: Text(
              _reasonError!,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        TextField(
          controller: _reasonController,
          maxLength: 1000,
          minLines: 5,
          maxLines: 7,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,

          onChanged: (value) {
            if (_reasonError != null && value.trim().isNotEmpty) {
              setState(() {
                _reasonError = null;
              });
            }
          },

          decoration: InputDecoration(
            hintText: 'اكتب سبب اعتراضك هنا...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _reasonError != null
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFCBD5E1),
                width: _reasonError != null ? 1.5 : 1,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _reasonError != null
                    ? const Color(0xFFDC2626)
                    : primaryColor,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

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
