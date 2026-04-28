import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'vehicle_details_screen.dart';

class AllVehiclesScreen extends StatelessWidget {
  final String ownerId;

  const AllVehiclesScreen({
    super.key,
    required this.ownerId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7FAFF),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'كل المركبات',
          style: TextStyle(
            color: Color(0xFF071A3D),
            fontWeight: FontWeight.w800,
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
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: vehicles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = vehicles[index];
              final v = doc.data() as Map<String, dynamic>;

              final name = '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim();
              final plate = v['plateNumber'] ?? '';
              final year = v['year'] ?? '';
              final color = v['color'] ?? '';
              final chassis = v['chassisNumber'] ?? '';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VehicleDetailsScreen(
                        vehicleId: doc.id,
                        vehicleData: v,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE8EEF7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        name.isEmpty ? 'مركبة' : name,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Color(0xFF071A3D),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('اللوحة: $plate', textDirection: TextDirection.rtl),
                      Text('السنة: $year', textDirection: TextDirection.rtl),
                      Text('اللون: $color', textDirection: TextDirection.rtl),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text('Chassis: $chassis'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
