import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../reviews/admin_claim_details_screen.dart';

enum _ObjectionFilter { all, needsProcessing, processed }
enum _ObjectionSort { newestFirst, oldestFirst }

class _ObjectionListItem {
  const _ObjectionListItem({
    required this.objectionDocId,
    required this.displayId,
    required this.rawCaseId,
    required this.status,
    required this.createdAt,
    required this.userName,
    required this.phoneNumber,
    required this.carName,
    required this.plateNumber,
  });

  final String objectionDocId;
  final String displayId;
  final String rawCaseId;
  final String status;
  final DateTime? createdAt;
  final String userName;
  final String phoneNumber;
  final String carName;
  final String plateNumber;
}

class AdminObjectionsScreen extends StatefulWidget {
  const AdminObjectionsScreen({super.key});

  @override
  State<AdminObjectionsScreen> createState() =>
      _AdminObjectionsScreenState();
}

class _AdminObjectionsScreenState extends State<AdminObjectionsScreen> {
  // Existing CrashLens colors only.
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _buttonPrimary = Color(0xFF1E3A6E);
  static const Color _borderColor = Color(0xFFE8EEF7);
  static const Color _softBlue = Color(0xFFEAF2FF);
  static const Color _pendingBg = Color(0xFFEAF1FF);
  static const Color _successBg = Color(0xFFDCFCE7);
  static const Color _success = Color(0xFF16A34A);
  static const Color _danger = Color(0xFFDC2626);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  List<_ObjectionListItem> _items = const [];
  bool _isLoading = true;
  String? _errorMessage;
  _ObjectionFilter _filter = _ObjectionFilter.all;
  _ObjectionSort _sort = _ObjectionSort.newestFirst;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _listenToObjections();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _listenToObjections() {
    _subscription = _firestore.collection('objection').snapshots().listen(
      (snapshot) async {
        final currentLoad = ++_loadVersion;

        if (mounted) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        }

        try {
          final result = await Future.wait(
            snapshot.docs.map(_hydrateObjection),
          );

          if (!mounted || currentLoad != _loadVersion) return;

          setState(() {
            _items = result;
            _isLoading = false;
          });
        } catch (_) {
          if (!mounted || currentLoad != _loadVersion) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'تعذر تحميل الاعتراضات.';
          });
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر تحميل الاعتراضات.';
        });
      },
    );
  }

  Future<_ObjectionListItem> _hydrateObjection(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    final rawCaseId = (data['caseId'] ?? '').toString().trim();

    String userName = 'مستخدم';
    String phoneNumber = '—';
    String carName = 'مركبة';
    String plateNumber = '—';

    if (rawCaseId.isNotEmpty) {
      final caseDoc = await _resolveCase(rawCaseId);

      if (caseDoc != null) {
        final caseData = caseDoc.data() ?? {};
        final ownerId = (caseData['ownerId'] ?? '').toString().trim();
        final vehicleId = (caseData['vehicleId'] ?? '').toString().trim();

        if (ownerId.isNotEmpty) {
          try {
            final userSnap =
                await _firestore.collection('users').doc(ownerId).get();
            final user = userSnap.data();
            if (user != null) {
              final rawName = (user['name'] ?? '').toString().trim();
              final rawPhone =
                  (user['phoneNumber'] ?? '').toString().trim();
              if (rawName.isNotEmpty) userName = rawName;
              if (rawPhone.isNotEmpty) phoneNumber = rawPhone;
            }
          } catch (_) {}
        }

        if (vehicleId.isNotEmpty) {
          try {
            final vehicleSnap =
                await _firestore.collection('vehicles').doc(vehicleId).get();
            final vehicle = vehicleSnap.data();
            if (vehicle != null) {
              final make = (vehicle['make'] ?? '').toString().trim();
              final model = (vehicle['model'] ?? '').toString().trim();
              final combined = '$make $model'.trim();
              if (combined.isNotEmpty) carName = combined;

              final arabicPlate =
                  (vehicle['arabicPlateNumber'] ?? '').toString().trim();
              final normalPlate =
                  (vehicle['plateNumber'] ?? '').toString().trim();

              if (arabicPlate.isNotEmpty) {
                plateNumber = arabicPlate;
              } else if (normalPlate.isNotEmpty) {
                plateNumber = normalPlate;
              }
            }
          } catch (_) {}
        }
      }
    }

    final rawObjectionId =
        (data['objectionID'] ?? data['objectionId'] ?? '').toString().trim();

    final displayId = rawObjectionId.isNotEmpty
        ? _withHash(rawObjectionId)
        : _shortId(doc.id, 'O');

    return _ObjectionListItem(
      objectionDocId: doc.id,
      displayId: displayId,
      rawCaseId: rawCaseId,
      status: (data['objectionStatus'] ?? '').toString().trim(),
      createdAt: _dateFrom(data['createdAt']),
      userName: userName,
      phoneNumber: phoneNumber,
      carName: carName,
      plateNumber: plateNumber,
    );
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveCase(
    String rawCaseId,
  ) async {
    final id = rawCaseId.trim();

    // Important guard: prevents Firestore .doc('') from throwing
    // "A document path must be a non-empty string".
    if (id.isEmpty) return null;

    try {
      final byField = await _firestore
          .collection('accidentCase')
          .where('caseID', isEqualTo: id)
          .limit(1)
          .get();

      if (byField.docs.isNotEmpty) {
        return byField.docs.first;
      }
    } catch (_) {}

    try {
      final byId = await _firestore.collection('accidentCase').doc(id).get();
      return byId.exists ? byId : null;
    } catch (_) {
      return null;
    }
  }

  DateTime? _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _withHash(String value) =>
      value.startsWith('#') ? value : '#$value';

  String _shortId(String id, String prefix) {
    final clean = id.trim();
    if (clean.isEmpty) return '#$prefix-—';
    final short = clean.length > 8 ? clean.substring(0, 8) : clean;
    return '#$prefix-${short.toUpperCase()}';
  }

  bool _isProcessed(String rawStatus) {
    final status = rawStatus.trim();

    return status == 'تم قبول الاعتراض' ||
        status == 'تم رفض الاعتراض' ||
        status == 'مقبول' ||
        status == 'مقبولة' ||
        status == 'تمت الموافقة' ||
        status == 'approved' ||
        status == 'مرفوض' ||
        status == 'مرفوضة' ||
        status == 'rejected';
  }

  List<_ObjectionListItem> get _visibleItems {
    final query = _searchController.text.trim().toLowerCase();

    final result = _items.where((item) {
      final processed = _isProcessed(item.status);

      if (_filter == _ObjectionFilter.needsProcessing && processed) {
        return false;
      }
      if (_filter == _ObjectionFilter.processed && !processed) {
        return false;
      }

      if (query.isEmpty) return true;

      final searchable = [
        item.objectionDocId,
        item.displayId,
        item.userName,
        item.phoneNumber,
        item.carName,
        item.plateNumber,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();

    result.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return _sort == _ObjectionSort.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
    });

    return result;
  }

  int get _processedCount =>
      _items.where((item) => _isProcessed(item.status)).length;

  int get _needsProcessingCount => _items.length - _processedCount;

  double _scale(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return (width / 430.0).clamp(0.78, 1.08);
  }

  double _font(BuildContext context, double value) => value * _scale(context);

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: _primaryBlue,
            onRefresh: () async {
              await Future<void>.delayed(const Duration(milliseconds: 450));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16 * s,
                12 * s,
                16 * s,
                bottomPad + 110,
              ),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'الاعتراضات',
                    style: TextStyle(
                      color: _textDark,
                      fontSize: _font(context, 27),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(height: 3 * s),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'مراجعة جميع الاعتراضات المقدمة من المستخدمين',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: _font(context, 13),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: 16 * s),
                _tabs(),
                SizedBox(height: 12 * s),
                _searchAndFilter(),
                SizedBox(height: 10 * s),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_visibleItems.length} اعتراض',
                    style: TextStyle(
                      color: _textMuted,
                      fontSize: _font(context, 12.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: 10 * s),
                _content(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    final s = _scale(context);

    return Row(
      children: [
        Expanded(
          child: _tab(
            value: _ObjectionFilter.all,
            title: 'الكل',
            icon: Icons.layers_outlined,
            count: _items.length,
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: _tab(
            value: _ObjectionFilter.needsProcessing,
            title: 'بانتظار المراجعة',
            icon: Icons.schedule_rounded,
            count: _needsProcessingCount,
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: _tab(
            value: _ObjectionFilter.processed,
            title: 'تمت المراجعة',
            icon: Icons.check_circle_outline_rounded,
            count: _processedCount,
          ),
        ),
      ],
    );
  }

  Widget _tab({
    required _ObjectionFilter value,
    required String title,
    required IconData icon,
    required int count,
  }) {
    final s = _scale(context);
    final active = _filter == value;

    return InkWell(
      borderRadius: BorderRadius.circular(15 * s),
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58 * s,
        padding: EdgeInsets.symmetric(horizontal: 7 * s),
        decoration: BoxDecoration(
          color: active ? _buttonPrimary : Colors.white,
          borderRadius: BorderRadius.circular(15 * s),
          border: Border.all(
            color: active ? _buttonPrimary : _borderColor,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17 * s,
              color: active ? Colors.white : _textDark,
            ),
            SizedBox(width: 5 * s),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    color: active ? Colors.white : _textDark,
                    fontSize: _font(context, 11.5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(width: 5 * s),
            Container(
              constraints: BoxConstraints(minWidth: 27 * s),
              padding: EdgeInsets.symmetric(
                horizontal: 7 * s,
                vertical: 4 * s,
              ),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withOpacity(.14)
                    : _softBlue,
                borderRadius: BorderRadius.circular(20 * s),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? Colors.white : _buttonPrimary,
                  fontSize: _font(context, 10.5),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchAndFilter() {
    final s = _scale(context);

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48 * s,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15 * s),
              border: Border.all(color: _borderColor),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _textDark,
                fontSize: _font(context, 12.5),
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'ابحث برقم الاعتراض، اسم المستخدم أو رقم اللوحة...',
                hintStyle: TextStyle(
                  color: _textMuted,
                  fontSize: _font(context, 11.5),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: _textMuted,
                  size: 23 * s,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12 * s,
                  vertical: 13 * s,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 9 * s),
        InkWell(
          borderRadius: BorderRadius.circular(15 * s),
          onTap: _showSortSheet,
          child: Container(
            height: 48 * s,
            padding: EdgeInsets.symmetric(horizontal: 12 * s),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15 * s),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  color: _buttonPrimary,
                  size: 20 * s,
                ),
                SizedBox(width: 5 * s),
                Text(
                  'فلتر',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: _font(context, 12),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 2 * s),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _buttonPrimary,
                  size: 20 * s,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showSortSheet() async {
    final selected = await showModalBottomSheet<_ObjectionSort>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final s = _scale(sheetContext);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              18 * s,
              14 * s,
              18 * s,
              MediaQuery.paddingOf(sheetContext).bottom + 18 * s,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24 * s),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42 * s,
                  height: 4 * s,
                  decoration: BoxDecoration(
                    color: _borderColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                SizedBox(height: 15 * s),
                Text(
                  'ترتيب الاعتراضات',
                  style: TextStyle(
                    color: _textDark,
                    fontSize: _font(sheetContext, 17),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 12 * s),
                _sortTile(
                  sheetContext,
                  title: 'الأحدث أولاً',
                  icon: Icons.south_rounded,
                  value: _ObjectionSort.newestFirst,
                ),
                SizedBox(height: 8 * s),
                _sortTile(
                  sheetContext,
                  title: 'الأقدم أولاً',
                  icon: Icons.north_rounded,
                  value: _ObjectionSort.oldestFirst,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _sort = selected);
    }
  }

  Widget _sortTile(
    BuildContext sheetContext, {
    required String title,
    required IconData icon,
    required _ObjectionSort value,
  }) {
    final s = _scale(sheetContext);
    final active = _sort == value;

    return InkWell(
      borderRadius: BorderRadius.circular(14 * s),
      onTap: () => Navigator.pop(sheetContext, value),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 13 * s,
          vertical: 12 * s,
        ),
        decoration: BoxDecoration(
          color: active ? _pendingBg : _pageBg,
          borderRadius: BorderRadius.circular(14 * s),
          border: Border.all(
            color: active ? _primaryBlue : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: _buttonPrimary, size: 21 * s),
            SizedBox(width: 10 * s),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: _textDark,
                  fontSize: _font(sheetContext, 13.5),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: active ? _primaryBlue : _textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(
          child: CircularProgressIndicator(color: _primaryBlue),
        ),
      );
    }

    if (_errorMessage != null) {
      return _messageCard(
        icon: Icons.error_outline_rounded,
        title: _errorMessage!,
      );
    }

    final items = _visibleItems;

    if (items.isEmpty) {
      return _messageCard(
        icon: Icons.inbox_outlined,
        title: 'لا توجد اعتراضات مطابقة',
      );
    }

    return Column(
      children: [
        for (final item in items) ...[
          _objectionCard(item),
          SizedBox(height: 10 * _scale(context)),
        ],
      ],
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String title,
  }) {
    final s = _scale(context);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 35 * s),
      padding: EdgeInsets.all(24 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18 * s),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Icon(icon, color: _textMuted, size: 32 * s),
          SizedBox(height: 10 * s),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textMuted,
              fontSize: _font(context, 13.5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectionCard(_ObjectionListItem item) {
    final s = _scale(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 355;

        return InkWell(
          borderRadius: BorderRadius.circular(18 * s),
          onTap: () {
            if (item.rawCaseId.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'هذا الاعتراض لا يحتوي على حالة مرتبطة.',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminClaimDetailsScreen(
                  objectionId: item.objectionDocId,
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: 12 * s,
              vertical: 11 * s,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18 * s),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.035),
                  blurRadius: 12 * s,
                  offset: Offset(0, 5 * s),
                ),
              ],
            ),
            child: compact
                ? _compactCardContent(item)
                : _wideCardContent(item),
          ),
        );
      },
    );
  }

  Widget _wideCardContent(_ObjectionListItem item) {
    final s = _scale(context);

    return Row(
      children: [
        Expanded(flex: 31, child: _userBlock(item)),
        SizedBox(width: 7 * s),
        Expanded(flex: 29, child: _vehicleBlock(item)),
        SizedBox(width: 7 * s),
        Expanded(flex: 28, child: _statusBlock(item)),
        SizedBox(width: 5 * s),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Icon(
            Icons.chevron_left_rounded,
            color: _buttonPrimary,
            size: 27 * s,
          ),
        ),
      ],
    );
  }

  Widget _compactCardContent(_ObjectionListItem item) {
    final s = _scale(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _userBlock(item)),
            SizedBox(width: 6 * s),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Icon(
                Icons.chevron_left_rounded,
                color: _buttonPrimary,
                size: 25 * s,
              ),
            ),
          ],
        ),
        SizedBox(height: 9 * s),
        Container(height: 1, color: _borderColor),
        SizedBox(height: 9 * s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _vehicleBlock(item)),
            SizedBox(width: 10 * s),
            Expanded(child: _statusBlock(item)),
          ],
        ),
      ],
    );
  }

  Widget _userBlock(_ObjectionListItem item) {
    final s = _scale(context);

    return Row(
      children: [
        Container(
          width: 43 * s,
          height: 43 * s,
          decoration: const BoxDecoration(
            color: _softBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_rounded,
            color: _textMuted,
            size: 27 * s,
          ),
        ),
        SizedBox(width: 7 * s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: _textDark,
                  fontSize: _font(context, 12.5),
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3 * s),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  item.phoneNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: _font(context, 10.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vehicleBlock(_ObjectionListItem item) {
    final s = _scale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            item.displayId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _textDark,
              fontSize: _font(context, 12),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(height: 4 * s),

        // Same external information as the cases page:
        // vehicle type + plate only. No objection reason/case number here.
        _iconText(
          Icons.directions_car_outlined,
          item.carName,
        ),
        SizedBox(height: 3 * s),
        _iconText(
          Icons.credit_card_outlined,
          item.plateNumber,
        ),
      ],
    );
  }

  Widget _iconText(IconData icon, String value) {
    final s = _scale(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _textMuted,
              fontSize: _font(context, 10.5),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: 5 * s),
        Icon(
          icon,
          color: _textMuted,
          size: 15 * s,
        ),
      ],
    );
  }

  Widget _statusBlock(_ObjectionListItem item) {
    final s = _scale(context);
    final processed = _isProcessed(item.status);

    final bg = processed ? _successBg : _pendingBg;
    final fg = processed ? _success : _buttonPrimary;
    final icon = processed
        ? Icons.check_circle_outline_rounded
        : Icons.schedule_rounded;
    final label = processed ? 'تمت المراجعة' : 'بانتظار المراجعة';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 8 * s,
            vertical: 6 * s,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20 * s),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15 * s, color: fg),
              SizedBox(width: 4 * s),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontSize: _font(context, 10),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 6 * s),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _formatDateTime(item.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: _font(context, 9.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 4 * s),
            Icon(
              Icons.calendar_month_outlined,
              color: _textMuted,
              size: 14 * s,
            ),
          ],
        ),
      ],
    );
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '—';

    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} • '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
