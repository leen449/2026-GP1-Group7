import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EligibleObjectionCase {
  const EligibleObjectionCase({
    required this.caseId,
    required this.reportId,
    required this.issuedAt,
    required this.totalCost,
  });

  final String caseId;
  final String reportId;
  final DateTime issuedAt;
  final num totalCost;
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

  Future<void> _loadEligibleCases() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = _auth.currentUser;
      debugPrint('Current user UID: ${currentUser?.uid}');

      if (currentUser == null) {
        throw Exception('يجب تسجيل الدخول أولًا.');
      }

      /*
       * 1. إحضار حالات المستخدم التي حالتها "تم الفحص" فقط.
       */
      final casesSnapshot = await _firestore
          .collection('accidentCase')
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'تم الفحص')
          .get();

      final List<EligibleObjectionCase> eligibleCases = [];

      /*
       * 2. فحص كل حالة:
       * - هل سبق تقديم اعتراض عليها؟
       * - هل يوجد تقرير مرتبط بها؟
       * - هل ما زال التقرير داخل مهلة 10 أيام؟
       */
      for (final caseDocument in casesSnapshot.docs) {
        final caseData = caseDocument.data();

        final String caseId =
            (caseData['caseID'] as String?)?.trim().isNotEmpty == true
            ? caseData['caseID'] as String
            : caseDocument.id;

        /*
         * التحقق من عدم وجود اعتراض سابق لنفس الحالة.
         */
        final existingObjection = await _firestore
            .collection('objection')
            .where('caseId', isEqualTo: caseId)
            .limit(1)
            .get();

        if (existingObjection.docs.isNotEmpty) {
          continue;
        }

        /*
         * إحضار التقرير المرتبط بالحالة.
         */
        final reportSnapshot = await _firestore
            .collection('reports')
            .where('caseId', isEqualTo: caseId)
            .limit(1)
            .get();

        if (reportSnapshot.docs.isEmpty) {
          continue;
        }

        final reportDocument = reportSnapshot.docs.first;
        final reportData = reportDocument.data();

        final dynamic issuedAtValue = reportData['issuedAt'];

        if (issuedAtValue is! Timestamp) {
          continue;
        }

        final DateTime issuedAt = issuedAtValue.toDate();
        final DateTime objectionDeadline = issuedAt.add(
          const Duration(days: 10),
        );

        /*
         * إذا انتهت مدة الاعتراض، لا نعرض الحالة.
         */
        if (DateTime.now().isAfter(objectionDeadline)) {
          continue;
        }

        final dynamic totalCostValue = reportData['totalCost'];

        final num totalCost = totalCostValue is num ? totalCostValue : 0;

        eligibleCases.add(
          EligibleObjectionCase(
            caseId: caseId,
            reportId: reportDocument.id,
            issuedAt: issuedAt,
            totalCost: totalCost,
          ),
        );
      }

      /*
       * ترتيب الأحدث أولًا.
       */
      eligibleCases.sort(
        (first, second) => second.issuedAt.compareTo(first.issuedAt),
      );

      if (!mounted) return;

      setState(() {
        _eligibleCases = eligibleCases;
        _isLoading = false;
      });
    } on FirebaseException catch (error) {
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
      /*
       * إعادة التحقق قبل الإنشاء لمنع تكرار الاعتراض
       * إذا تغيرت البيانات أثناء فتح الصفحة.
       */
      final existingObjection = await _firestore
          .collection('objection')
          .where('caseId', isEqualTo: _selectedCaseId)
          .limit(1)
          .get();

      if (existingObjection.docs.isNotEmpty) {
        throw Exception('سبق تقديم اعتراض على هذه الحالة.');
      }

      /*
       * إعادة التحقق من حالة الكيس.
       */
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

      if (caseData?['status'] != 'تم الفحص') {
        throw Exception('لا يمكن تقديم اعتراض لأن حالة الكيس تغيرت.');
      }

      /*
       * إعادة التحقق من مهلة التقرير.
       */
      final reportSnapshot = await _firestore
          .collection('reports')
          .where('caseId', isEqualTo: _selectedCaseId)
          .limit(1)
          .get();

      if (reportSnapshot.docs.isEmpty) {
        throw Exception('لم يتم العثور على تقرير لهذه الحالة.');
      }

      final reportData = reportSnapshot.docs.first.data();
      final dynamic issuedAtValue = reportData['issuedAt'];

      if (issuedAtValue is! Timestamp) {
        throw Exception('تاريخ إصدار التقرير غير صالح.');
      }

      final DateTime issuedAt = issuedAtValue.toDate();
      final DateTime deadline = issuedAt.add(const Duration(days: 10));

      if (DateTime.now().isAfter(deadline)) {
        throw Exception('انتهت المدة المحددة لتقديم اعتراض على هذه الحالة.');
      }

      /*
       * إنشاء معرف مستقل وعشوائي للاعتراض.
       */
      final objectionReference = _firestore.collection('objection').doc();

      await objectionReference.set({
        'caseId': _selectedCaseId,
        'reason': reason,
        'objectionStatus': 'قيد المراجعة',
        'adminFeedback': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _showMessage('تم تقديم الاعتراض بنجاح.', isError: false);

      /*
       * إزالة الحالة من القائمة لأنها لم تعد مؤهلة
       * لاعتراض جديد.
       */
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
                borderRadius: BorderRadius.circular(14),
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
                            'تم الفحص',
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
                        label: 'تاريخ إصدار التقرير',
                        value:
                            '${item.issuedAt.day}/${item.issuedAt.month}/${item.issuedAt.year}',
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
                        label: 'إجمالي المبلغ',
                        value: '${item.totalCost} ريال',
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
