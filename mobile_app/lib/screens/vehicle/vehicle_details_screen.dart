import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VehicleDetailsScreen extends StatelessWidget {
  final String vehicleId;
  final Map<String, dynamic> vehicleData;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleData,
  });

  Future<void> _deleteVehicle(BuildContext context) async {
    await FirebaseFirestore.instance.collection('vehicles').doc(vehicleId).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFB9C3CF)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: Color(0xFF0B8F2F),
                child: Icon(Icons.check, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              const Text(
                'تم حذف المركبة بنجاح',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF071A3D),
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 114,
                height: 40,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: const Text(
                    'حسنًا',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'حذف المركبة؟',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: Color(0xFF071A3D),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'هل أنت متأكد أنك تريد حذف هذه المركبة؟',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: Color(0xFF071A3D),
            fontWeight: FontWeight.w600,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, false),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEDEDED),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Text('إلغاء'),
            ),
          ),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE33B4E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Text('حذف'),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteVehicle(context);
    }
  }

  Widget _infoBox(String title, String value, {bool ltr = false}) {
    return Expanded(
      child: Container(
        height: 86,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFF8B97AA),
              ),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value.toString().trim().isEmpty ? '—' : value.toString(),
                textAlign: ltr ? TextAlign.left : TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF071A3D),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideInfoBox(String title, String value, {bool ltr = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xFF8B97AA),
            ),
          ),
          const SizedBox(height: 7),
          Directionality(
            textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
            child: Text(
              value.toString().trim().isEmpty ? '—' : value.toString(),
              textAlign: ltr ? TextAlign.left : TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF071A3D),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = vehicleData['color'] ?? '';
    final make = vehicleData['make'] ?? '';
    final model = vehicleData['model'] ?? '';
    final year = vehicleData['year'] ?? '';
    final plateNumber = vehicleData['plateNumber'] ?? '';
    final arabicPlateNumber = vehicleData['arabicPlateNumber'] ?? '';
    final chassisNumber = vehicleData['chassisNumber'] ?? '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF7FAFF),
          surfaceTintColor: const Color(0xFFF7FAFF),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'تفاصيل المركبة',
            style: TextStyle(
              color: Color(0xFF071A3D),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          iconTheme: const IconThemeData(color: Color(0xFF071A3D)),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteDialog(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(
                    'حذف',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: ListView(
            children: [
              Container(
                height: 135,
                alignment: Alignment.center,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Image.asset(
                    'assets/images/allcar_card.PNG',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$make $model'.trim().isEmpty ? 'مركبة' : '$make $model'.trim(),
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: Color(0xFF071A3D),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _infoBox('اللون', color),
                  const SizedBox(width: 12),
                  _infoBox('الشركة', make),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _infoBox('الطراز', model),
                  const SizedBox(width: 12),
                  _infoBox('السنة', year, ltr: true),
                ],
              ),
              const SizedBox(height: 12),
              _wideInfoBox('رقم اللوحة ', plateNumber, ltr: true),
              const SizedBox(height: 12),
              _wideInfoBox('رقم اللوحة ', arabicPlateNumber),
              const SizedBox(height: 12),
              _wideInfoBox('رقم الهيكل', chassisNumber, ltr: true),
            ],
          ),
        ),
      ),
    );
  }
}
