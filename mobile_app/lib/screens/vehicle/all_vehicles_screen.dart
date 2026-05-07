import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AllVehiclesScreen extends StatelessWidget {
  final String ownerId;

  const AllVehiclesScreen({super.key, required this.ownerId});

  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF2563EB);
  static const Color _dangerRed = Colors.red;

  Future<void> _archiveVehicle(BuildContext context, String vehicleId) async {
    final size = MediaQuery.of(context).size;
    final double screenWidth = size.width;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: _dangerRed,
                        size: screenWidth * 0.08,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'تأكيد حذف المركبة',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: screenWidth * 0.045,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF071A3D),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: screenWidth * 0.04),

                  Text(
                    'سيتم حذف المركبة من حسابك. هل ترغب بالمتابعة؟',
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: screenWidth * 0.035,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),

                  SizedBox(height: screenWidth * 0.06),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEDEDED),
                            foregroundColor: Colors.black87,
                            padding: EdgeInsets.symmetric(
                              vertical: screenWidth * 0.03,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'إلغاء',
                            style: TextStyle(fontSize: screenWidth * 0.04),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A6E),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: screenWidth * 0.03,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'تأكيد',
                            style: TextStyle(fontSize: screenWidth * 0.04),
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
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('vehicles')
        .doc(vehicleId)
        .update({
          'isArchived': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    if (!context.mounted) return;

    final sh = MediaQuery.of(context).size.height;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('تم حذف المركبة بنجاح', textDirection: TextDirection.rtl),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.fromLTRB(16, 0, 16, sh * 0.80),
      ),
    );
  }

  String _vehicleName(Map<String, dynamic> v) {
    return '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        surfaceTintColor: _pageBg,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.arrow_forward_ios_rounded,
              color: _textDark,
              size: 22,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        centerTitle: true,
        title: const Text(
          'مركباتي',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: _textDark,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('vehicles')
            .where('ownerId', isEqualTo: ownerId)
            .where('isArchived', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              snapshot.error.toString(),
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3A6E)),
            );
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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            itemCount: vehicles.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _counterCard(vehicles.length);
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
    );
  }

  Widget _counterCard(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE8EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.directions_car_filled_outlined,
              color: _primaryBlue,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$count',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: _primaryBlue,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'مركبة مسجلة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'جميع مركباتك في مكان واحد',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
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
    final name = _vehicleName(vehicleData);
    final year = vehicleData['year'] ?? '';
    final color = vehicleData['color'] ?? '';
    final plate =
        vehicleData['arabicPlateNumber'] ?? vehicleData['plateNumber'] ?? '';
    final chassis = vehicleData['chassisNumber'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F8FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Image.asset(
              'assets/images/allcar_card.PNG',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  name.isEmpty ? 'مركبة' : name,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _detailLine('السنة', year),
                _detailLine('اللون', color),
                _detailLine('رقم اللوحة', plate),
                _detailLine('رقم الهيكل', chassis, ltrValue: true),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => _archiveVehicle(context, vehicleId),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: _dangerRed,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String title, dynamic value, {bool ltrValue = false}) {
    final textValue = value == null || value.toString().trim().isEmpty
        ? '—'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title:',
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Directionality(
              textDirection: ltrValue ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                textValue,
                textAlign: TextAlign.right,
                maxLines: 2,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
