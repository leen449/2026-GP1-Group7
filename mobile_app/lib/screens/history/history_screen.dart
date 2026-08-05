import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../submit_case/Case_Details_Screen.dart';

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

    /*
     * صفحة تفاصيل الاعتراض ستنشئها صديقتك لاحقًا.
     * بعد إنشائها نستبدل هذا الـ SnackBar بعملية Navigator.push.
     */
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'صفحة تفاصيل الاعتراض قيد الإعداد',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
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
            Text(
              title,
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

    final _StatusStyle statusStyle =
        _getStatusStyle(record.status);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCase ? 'رقم الحالة' : 'رقم الاعتراض',
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        record.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildStatusBadge(statusStyle),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isCase
                      ? Icons.folder_copy_outlined
                      : Icons.description_outlined,
                  color: _primaryBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تاريخ التقديم',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatArabicDate(record.createdAt),
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _openRecordDetails(record),
              iconAlignment: IconAlignment.end,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,

size: 16,
              ),
              label: const Text(
                'عرض التفاصيل',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryBlue,
                side: const BorderSide(
                  color: _primaryBlue,
                  width: 1.2,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(_StatusStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            style.icon,
            color: style.foregroundColor,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            style.label,
            style: TextStyle(
              color: style.foregroundColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  _StatusStyle _getStatusStyle(String originalStatus) {
    final String normalizedStatus =
        originalStatus.trim().toLowerCase();

    if (normalizedStatus.contains('رفض') ||
        normalizedStatus.contains('فشل')) {
      return const _StatusStyle(
        label: 'مرفوضة',
        foregroundColor: Color(0xFFDC2626),
        backgroundColor: Color(0xFFFEE2E2),
        icon: Icons.cancel_outlined,
      );
    }

    if (normalizedStatus.contains('تمت المعالجة') ||
        normalizedStatus.contains('تمت المراجعة') ||
        normalizedStatus.contains('تم المراجعة') ||
        normalizedStatus.contains('تم الفحص') ||
        normalizedStatus.contains('مقبول')) {
      return const _StatusStyle(
        label: 'تمت المعالجة',
        foregroundColor: Color(0xFF16A34A),
        backgroundColor: Color(0xFFDCFCE7),
        icon: Icons.check_circle_outline_rounded,
      );
    }

    return const _StatusStyle(
      label: 'قيد المراجعة',
      foregroundColor: Color(0xFFD97706),
      backgroundColor: Color(0xFFFEF3C7),
      icon: Icons.hourglass_top_rounded,
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

class _StatusStyle {
  const _StatusStyle({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.icon,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final IconData icon;
}