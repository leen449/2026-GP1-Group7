import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../vehicle/all_vehicles_screen.dart';


class VehicleDetailsScreen extends StatelessWidget {
  final String vehicleId;
  final Map<String, dynamic> vehicleData;

  const VehicleDetailsScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleData,
  });

  static const Color _pageBg = Color(0xFFF8FBFF);
  static const Color _textDark = Color(0xFF081A3D);
  static const Color _textMuted = Color(0xFF8A96A8);
  static const Color _blue = Color(0xFF2563EB);

  Future<void> _archiveVehicle(String id) async {
    await FirebaseFirestore.instance.collection('vehicles').doc(id).update({
      'isArchived': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = vehicleData['ownerId'] ?? '';

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  ),
                  const Spacer(),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'مركباتي',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _textDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'إدارة ومتابعة جميع مركباتك بسهولة',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 15,
                          color: _textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 22),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
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
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: vehicles.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _summaryCard(vehicles.length);
                        }

                        final doc = vehicles[index - 1];
                        final v = doc.data() as Map<String, dynamic>;

                        return _vehicleCard(
                          context: context,
                          vehicleId: doc.id,
                          make: v['make'] ?? '',
                          model: v['model'] ?? '',
                          year: v['year'] ?? '',
                          color: v['color'] ?? '',
                          plate: v['plateNumber'] ?? '',
                          chassis: v['chassisNumber'] ?? '',
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(int count) {
    return Container(
      height: 145,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD8E8FA)),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.directions_car, color: _blue, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: _blue,
                  ),
                ),
                const Text(
                  'مركبات مسجلة',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'جميع مركباتك في مكان واحد مع معلومات محدثة دائماً',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    color: _textMuted,
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

  Widget _vehicleCard({
    required BuildContext context,
    required String vehicleId,
    required String make,
    required String model,
    required String year,
    required String color,
    required String plate,
    required String chassis,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7EEF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Image.asset(
            'assets/images/car_card.jpg',
            width: 90,
            height: 70,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$make $model'.trim(),
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
                _detailLine('اللوحة', plate, ltr: true),
                _detailLine('رقم الهيكل', chassis, ltr: true),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => _archiveVehicle(vehicleId),
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          ),
        ],
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
              fontSize: 13,
              color: _textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Directionality(
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: _textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
