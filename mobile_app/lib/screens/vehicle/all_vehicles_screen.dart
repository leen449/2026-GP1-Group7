import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AllVehiclesScreen extends StatelessWidget {
  final String ownerId;

String _toArabicDigits(String input) {
  const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  for (int i = 0; i < english.length; i++) {
    input = input.replaceAll(english[i], arabic[i]);
  }
  return input;
}

  const AllVehiclesScreen({
    super.key,
    required this.ownerId,
  });

  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _softBlue = Color(0xFFEAF2FF);

  Future<void> _archiveVehicle(BuildContext context, String vehicleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'تأكيد الحذف',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        content: const Text(
          'هل تريد حذف هذه المركبة؟',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'حذف',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance.collection('vehicles').doc(vehicleId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم حذف المركبة',
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  void _showVehicleCard(
    BuildContext context,
    String vehicleId,
    Map<String, dynamic> v,
  ) {
    final make = v['make'] ?? '';
    final model = v['model'] ?? '';
    final year = v['year'] ?? '';
    final color = v['color'] ?? '';
    final plate = v['plateNumber'] ?? '';
    final arabicPlate = v['arabicPlateNumber'] ?? '';
    final chassis = v['chassisNumber'] ?? '';

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'vehicle_details',
      barrierColor: Colors.black.withOpacity(0.28),
      pageBuilder: (_, __, ___) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE4EDF8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const Spacer(),
                        const Text(
                          'تفاصيل المركبة',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: _textDark,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: BoxDecoration(
                          color: _softBlue,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Image.asset(
                            'assets/images/allcar_card.PNG',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        '$make $model'.trim().isEmpty
                            ? 'مركبة'
                            : '$make $model'.trim(),
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _popupInfoRow('الشركة', make),
                    _popupInfoRow('الطراز', model),
                    _popupInfoRow('السنة', year),
                    _popupInfoRow('اللون', color),
                    _popupInfoRow('اللوحة ', plate, ltr: true),
                    if (arabicPlate.toString().trim().isNotEmpty)
                      _popupInfoRow('اللوحة ', arabicPlate),
                    _popupInfoRow('رقم الهيكل', chassis, ltr: true),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _archiveVehicle(context, vehicleId),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text(
                          'حذف المركبة',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE33B4E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _popupInfoRow(String title, String value, {bool ltr = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF7)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value.toString().trim().isEmpty ? '—' : value.toString(),
                textAlign: ltr ? TextAlign.left : TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int count) {
    return Container(
      height: 175,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD8E8FA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.directions_car_filled_outlined,
              color: _primaryBlue,
              size: 32,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
  _toArabicDigits(count.toString()),

                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: _primaryBlue,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'مركبة مسجلة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'جميع مركباتك في مكان واحد ',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vehicleListCard({
    required BuildContext context,
    required String vehicleId,
    required Map<String, dynamic> vehicleData,
  }) {
    final make = vehicleData['make'] ?? '';
    final model = vehicleData['model'] ?? '';
    final year = vehicleData['year'] ?? '';
    final color = vehicleData['color'] ?? '';
    final plate = vehicleData['plateNumber'] ?? '';
    final arabicPlate = vehicleData['arabicPlateNumber'] ?? '';
    final chassis = vehicleData['chassisNumber'] ?? '';

    return GestureDetector(
      onTap: () => _showVehicleCard(context, vehicleId, vehicleData),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7EEF8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.045),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8FF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/images/allcar_card.PNG',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$make $model'.trim().isEmpty
                        ? 'مركبة'
                        : '$make $model'.trim(),
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _detailLine('السنة', year),
                  _detailLine('اللون', color),
                  _detailLine('اللوحة ', plate, ltr: true),
                  if (arabicPlate.toString().trim().isNotEmpty)
                    _detailLine('اللوحة ', arabicPlate),
                  _detailLine('رقم الهيكل', chassis, ltr: true),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: _softBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: _primaryBlue,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(String title, String value, {bool ltr = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            '$title: ',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontSize: 12.5,
              color: _textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value.toString().trim().isEmpty ? '—' : value.toString(),
                textAlign: ltr ? TextAlign.left : TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: _textDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          elevation: 0,
          surfaceTintColor: _pageBg,
          centerTitle: true,
          iconTheme: const IconThemeData(color: _textDark),
          title: const Text(
            'مركباتي',
            style: TextStyle(
              color: _textDark,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('vehicles')
              .where('ownerId', isEqualTo: ownerId)
              .where('isArchived', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final vehicles = snapshot.data?.docs ?? [];

            if (vehicles.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد مركبات مسجلة حتى الآن',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              itemCount: vehicles.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _summaryCard(vehicles.length);
                }

                final doc = vehicles[index - 1];
                final v = doc.data() as Map<String, dynamic>;

                return _vehicleListCard(
                  context: context,
                  vehicleId: doc.id,
                  vehicleData: v,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
