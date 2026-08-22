import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../submit_case/Case_Details_Screen.dart';
import '../objection/objection_details_screen.dart';

enum HistoryRecordType {
  caseRecord,
  objection,
}

enum HistoryViewFilter {
  all,
  cases,
  objections,
}

enum HistorySortOrder {
  newestFirst,
  oldestFirst,
}

class HistoryRecord {
  const HistoryRecord({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    this.relatedCaseId,
  });

  final String id;
  final HistoryRecordType type;
  final String status;
  final DateTime? createdAt;

  // يُستخدم عند فتح تفاصيل الاعتراض مستقبلًا.
  final String? relatedCaseId;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ألوان موحدة مع بقية صفحات التطبيق.
  static const Color _pageBackground = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _navy = Color(0xFF061943);
  static const Color _cardBorder = Color(0xFFE8EEF7);

  bool _isLoading = true;
  String? _errorMessage;

  List<HistoryRecord> _records = [];

  HistoryViewFilter _selectedView = HistoryViewFilter.all;
  HistorySortOrder _sortOrder = HistorySortOrder.newestFirst;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // ─────────────────────────────────────────────────────────────
  // تحميل جميع حالات واعتراضات المستخدم
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        throw Exception('يجب تسجيل الدخول أولًا.');
      }

      /*
       * بعض صفحات المشروع تحفظ ownerId باستخدام Firebase Auth UID،
       * وبعضها تستخدم document ID الخاص بالمستخدم داخل users.
       *
       * لذلك نجمع الاحتمالين حتى تظهر جميع بيانات المستخدم بدون
       * التأثير على الصفحات القديمة أو الجديدة.
       */
      final Set<String> possibleOwnerIds = {
        currentUser.uid,
      };

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

      /*
       * نجلب الحالات لكل ownerId بشكل منفصل ثم ندمجها محليًا.
       * لم نستخدم orderBy حتى لا تحتاج الصفحة Composite Index جديدًا.
       */
      final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
          uniqueCaseDocuments = {};

      for (final ownerId in possibleOwnerIds) {
        final caseSnapshot = await _firestore
            .collection('accidentCase')
            .where('ownerId', isEqualTo: ownerId)
            .get();

        for (final document in caseSnapshot.docs) {
          uniqueCaseDocuments[document.id] = document;
        }
      }

      final List<HistoryRecord> caseRecords = [];
      final Set<String> userCaseIds = {};

      for (final document in uniqueCaseDocuments.values) {
        final data = document.data();

        /*
         * لا نعرض الحالة المؤقتة التي تُنشأ أثناء OCR.
         * تظهر فقط الحالات التي أرسلها المستخدم فعليًا.
         */
        final bool isSubmitted = data['isSubmitted'] == true;

        if (!isSubmitted) {
          continue;
        }

        final String caseId =
            data['caseID']?.toString().trim().

isNotEmpty == true
                ? data['caseID'].toString().trim()
                : document.id;

        final String status =
            data['status']?.toString().trim().isNotEmpty == true
                ? data['status'].toString().trim()
                : 'قيد المراجعة';

        final DateTime? createdAt = _timestampToDate(data['createdAt']);

        userCaseIds.add(caseId);
        userCaseIds.add(document.id);

        caseRecords.add(
          HistoryRecord(
            id: caseId,
            type: HistoryRecordType.caseRecord,
            status: status,
            createdAt: createdAt,
          ),
        );
      }

      /*
       * الاعتراض لا يحتوي ownerId في الكود الحالي.
       * لذلك نحمّل الاعتراضات ونحتفظ فقط بالاعتراضات المرتبطة
       * بحالات المستخدم الحالي.
       */
      final List<HistoryRecord> objectionRecords = [];

      if (userCaseIds.isNotEmpty) {
        final objectionSnapshot =
            await _firestore.collection('objection').get();

        for (final document in objectionSnapshot.docs) {
          final data = document.data();

          final String relatedCaseId =
              data['caseId']?.toString().trim() ?? '';

          if (!userCaseIds.contains(relatedCaseId)) {
            continue;
          }

          final String status =
              data['objectionStatus']?.toString().trim().isNotEmpty == true
                  ? data['objectionStatus'].toString().trim()
                  : 'قيد المراجعة';

          objectionRecords.add(
            HistoryRecord(
              id: document.id,
              type: HistoryRecordType.objection,
              status: status,
              createdAt: _timestampToDate(data['createdAt']),
              relatedCaseId: relatedCaseId,
            ),
          );
        }
      }

      final List<HistoryRecord> allRecords = [
        ...caseRecords,
        ...objectionRecords,
      ];

      if (!mounted) return;

      setState(() {
        _records = allRecords;
        _isLoading = false;
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            error.message ?? 'حدث خطأ أثناء تحميل السجلات.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim();
      });
    }
  }

  DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // فلترة وترتيب السجلات محليًا
  // ─────────────────────────────────────────────────────────────
  List<HistoryRecord> get _visibleRecords {
    final filteredRecords = _records.where((record) {
      switch (_selectedView) {
        case HistoryViewFilter.all:
          return true;

        case HistoryViewFilter.cases:
          return record.type == HistoryRecordType.caseRecord;

        case HistoryViewFilter.objections:
          return record.type == HistoryRecordType.objection;
      }
    }).toList();

    filteredRecords.sort((first, second) {
      final firstDate =
          first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      final secondDate =
          second.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (_sortOrder == HistorySortOrder.newestFirst) {
        return secondDate.compareTo(firstDate);
      }

      return firstDate.compareTo(secondDate);
    });

    return filteredRecords;
  }

  // ─────────────────────────────────────────────────────────────
  // نافذة ترتيب السجلات
  // ─────────────────────────────────────────────────────────────
  Future<void> _showSortOptions() async {
    final selectedOrder = await showModalBottomSheet<HistorySortOrder>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {

return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(bottomSheetContext).padding.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8E0EA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'ترتيب السجلات',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _buildSortOption(
                  context: bottomSheetContext,
                  title: 'الأحدث أولًا',
                  subtitle: 'عرض أحدث الحالات والاعتراضات في الأعلى',
                  icon: Icons.south_rounded,
                  value: HistorySortOrder.newestFirst,
                ),
                const SizedBox(height: 10),
                _buildSortOption(
                  context: bottomSheetContext,
                  title: 'الأقدم أولًا',
                  subtitle: 'عرض أقدم الحالات والاعتراضات في الأعلى',
                  icon: Icons.north_rounded,
                  value: HistorySortOrder.oldestFirst,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedOrder == null || !mounted) return;

    setState(() {
      _sortOrder = selectedOrder;
    });
  }

  Widget _buildSortOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required HistorySortOrder value,
  }) {
    final bool isSelected = _sortOrder == value;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, value),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEFF6FF)
                : _pageBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? _primaryBlue
                  : _cardBorder,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: _primaryBlue,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isSelected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: isSelected
                    ? _primaryBlue
                    : _textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // فتح صفحة التفاصيل
  // ─────────────────────────────────────────────────────────────
  
void _openRecordDetails(HistoryRecord record) {
  if (record.type == HistoryRecordType.caseRecord) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaseDetailsScreen(
          caseId: record.id,
        ),
      ),
    );

    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ObjectionDetailsScreen(
        objectionId: record.id,
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final double bottomNavigationSpace =
        MediaQuery.of(context).size.height * 0.13;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: _pageBackground,
          surfaceTintColor: _pageBackground,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: const Text(
            'السجلات',
            style: TextStyle(
              color: _textDark,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _loadHistory,
            color: _primaryBlue,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                18,
                4,
                18,
                bottomNavigationSpace,
              ),
              children: [
                const Text(
                  'يمكنك متابعة جميع الحالات والاعتراضات السابقة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(
                      child: _buildCategoryTabs(),
                    ),
                    const SizedBox(width: 10),

                    // زر الفلتر أيقونة فقط.
                    Tooltip(
                      message: 'ترتيب السجلات',
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: _showSortOptions,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 54,
                            height: 54,

decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _cardBorder,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withOpacity(0.035),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: _primaryBlue,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                _buildContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildCategoryTab(
              title: 'الكل',
              value: HistoryViewFilter.all,
            ),
          ),
          Expanded(
            child: _buildCategoryTab(
              title: 'الحالات',
              value: HistoryViewFilter.cases,
            ),
          ),
          Expanded(
            child: _buildCategoryTab(
              title: 'الاعتراضات',
              value: HistoryViewFilter.objections,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab({
    required String title,
    required HistoryViewFilter value,
  }) {
    final bool isSelected = _selectedView == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedView = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEFF6FF)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  color: isSelected
                      ? _primaryBlue
                      : _textDark,
                  fontSize: 14,
                  fontWeight: isSelected
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isSelected ? 28 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: _primaryBlue,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(
          child: CircularProgressIndicator(
            color: _primaryBlue,
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    final records = _visibleRecords;

if (records.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: records.map(_buildRecordCard).toList(),
    );
  }
Widget _buildRecordCard(HistoryRecord record) {
  final bool isCase =
      record.type == HistoryRecordType.caseRecord;

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openRecordDetails(record),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
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
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  // نفس سهم الـHome ورأسه لليسار
                  

                  // نفس Badge المستخدم في الـHome
                  Flexible(
                    child: _historyStatusBadge(
                      record.status,
                      isCase: isCase,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isCase
                              ? 'رقم الحالة'
                              : 'رقم الاعتراض',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            record.id,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _textDark,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                _formatArabicDate(
                                  record.createdAt,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _textDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // أيقونة تقويم  
                            const Icon(
                              Icons.calendar_month_outlined,
                              size: 16,
                              color: _textMuted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // نفس شكل الأيقونة الدائرية في الـHome
                  _historyRecordIcon(
                    record.status,
                    isCase: isCase,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // زر عرض التفاصيل
            Align(
  alignment: Alignment.centerLeft,
  child: InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => _openRecordDetails(record),
    child: const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.ltr,
        children: [
          Text(
            'عرض التفاصيل',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: _primaryBlue,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: _primaryBlue,
          ),
          SizedBox(width: 6),
          
        ],
      ),
    ),
  ),
),
          ],
        ),
      ),
    ),
  );
}
Widget _historyStatusBadge(
  String status, {
  required bool isCase,
}) {
  final s = status.trim();

  String displayStatus;
  Color bgColor;
  Color textColor;
  IconData icon;

  if (isCase) {
    // نفس الحالات والألوان والأيقونات الموجودة في Home
    if (s == 'مكتمل' ||
        s == 'تم الفحص' ||
        s == 'approved' ||
        s == 'completed') {
      displayStatus = 'تم الفحص';
bgColor = const Color(0xFFDCFCE7);
textColor = const Color(0xFF16A34A);
icon = Icons.check_circle_outline_rounded;
    } else if (s == 'قيد المراجعة' || s == 'pending') {
      displayStatus = 'قيد المراجعة';
      bgColor = const Color(0xFFEAF1FF);
      textColor = const Color(0xFF2563EB);
      icon = Icons.hourglass_empty_rounded;
    } else if (s == 'فشل الفحص' || s == 'ocr_failed') {
      displayStatus = 'فشل الفحص';
      bgColor = const Color(0xFFFFEEF0);
      textColor = Colors.red;
      icon = Icons.gpp_bad_outlined;
    } else if (s == 'تم المراجعة' || s == 'valid') {
      displayStatus = 'تم المراجعة';
      bgColor = const Color(0xFFDCFCE7);
      textColor = Colors.green;
      icon = Icons.check;
    } else {
      displayStatus = 'قيد التحليل';
      bgColor = const Color(0xFFFFF1E6);
      textColor = const Color(0xFFE27A2E);
      icon = Icons.access_time_rounded;
    }
  } else {
    // الاعتراضات بنفس Palette وأسلوب الـHome
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
      displayStatus =
          s.isEmpty ? 'تمت المعالجة' : s;
      bgColor = const Color(0xFFDCFCE7);
      textColor = Colors.green;
      icon = Icons.check;
    }
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
        Flexible(
          child: Text(
            displayStatus,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: textColor,
            ),
          ),
        ),
      ],
    ),
  );
}
Widget _historyRecordIcon(
  String status, {
  required bool isCase,
}) {
  final s = status.trim();

  Color bgColor;
  Color iconColor;
  IconData icon;

  if (!isCase) {
    if (s == 'قيد المراجعة' || s == 'pending') {
      bgColor = const Color(0xFFEAF1FF);
      iconColor = const Color(0xFF2E63D9);
      icon = Icons.assignment_outlined;
    } else if (s == 'مرفوض' ||
        s == 'مرفوضة' ||
        s == 'rejected') {
bgColor = const Color(0xFFFFEEF0);
      iconColor = Colors.red;
      icon = Icons.gpp_bad_outlined;
    } else {
      bgColor = const Color(0xFFDCFCE7);
      iconColor = Colors.green;
      icon = Icons.check_circle_outline_rounded;
    }
  } else if (s == 'مكتمل' ||
      s == 'تم الفحص' ||
      s == 'approved' ||
      s == 'completed') {
    bgColor = const Color(0xFFDCFCE7);
    iconColor = const Color(0xFF16A34A);
    
    icon = Icons.verified_user_outlined;
  } else if (s == 'قيد المراجعة' || s == 'pending') {
    bgColor = const Color(0xFFEAF1FF);
    iconColor = const Color(0xFF2E63D9);
    icon = Icons.search_rounded;
  } else if (s == 'فشل الفحص' || s == 'ocr_failed') {
    bgColor = const Color(0xFFFFEEF0);
    iconColor = Colors.red;
    icon = Icons.gpp_bad_outlined;
  } else if (s == 'تم المراجعة' || s == 'valid') {
    bgColor = const Color(0xFFDCFCE7);
    iconColor = Colors.green;
    icon = Icons.check_circle_outline_rounded;
  } else {
    bgColor = const Color(0xFFFFF1E6);
    iconColor = const Color(0xFFE27A2E);
    icon = Icons.description_outlined;
  }

  return Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: bgColor,
      shape: BoxShape.circle,
    ),
    child: Icon(
      icon,
      color: iconColor,
      size: 25,
    ),
  );
}


  

  String _formatArabicDate(DateTime? date) {
    if (date == null) {
      return 'غير محدد';
    }

    const List<String> arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    return '${date.day} ${arabicMonths[date.month - 1]} ${date.year}';
  }

  Widget _buildEmptyState() {
    String title;
    String subtitle;

    switch (_selectedView) {
      case HistoryViewFilter.all:
        title = 'لا توجد سجلات';
        subtitle =
            'ستظهر هنا الحالات والاعتراضات التي قمت بتقديمها.';
        break;

      case HistoryViewFilter.cases:
        title = 'لا توجد حالات';
        subtitle = 'لم تقم بإرسال أي حالة حتى الآن.';
        break;

      case HistoryViewFilter.objections:
        title = 'لا توجد اعتراضات';
        subtitle = 'لم تقم بتقديم أي اعتراض حتى الآن.';
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 34,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          Container(

width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inbox_outlined,
              color: _primaryBlue,
              size: 31,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 48,
          ),
          const SizedBox(height: 13),
          const Text(
            'تعذر تحميل السجلات',
            style: TextStyle(
              color: _textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _errorMessage ?? 'حدث خطأ غير متوقع.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

