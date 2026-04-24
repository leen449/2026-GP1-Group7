import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CaseDetailsScreen extends StatelessWidget {
  final String caseId;

  const CaseDetailsScreen({super.key, required this.caseId});

  static const Color _pageBg = Colors.white;
  static const Color _cardGrey = Color(0xFFF2F3F5);
  static const Color _textDark = Color(0xFF1E1E1E);
  static const Color _textMuted = Color(0xFF6B6B6B);
  static const Color _blue = Color(0xFF0B4A7D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textDark),
        title: const Text(
          'Case Details',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('accidentCase')
            .doc(caseId)
            .snapshots(),
        builder: (context, caseSnap) {
          if (caseSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!caseSnap.hasData || !caseSnap.data!.exists) {
            return const Center(child: Text('Case not found.'));
          }

          final caseData = caseSnap.data!.data() as Map<String, dynamic>;
          final vehicleId = caseData['vehicleId'] ?? '';
          final ownerId = caseData['ownerId'] ?? '';
          final najmReport =
              (caseData['najimReport'] as Map<String, dynamic>?) ?? {};

          final createdAt = caseData['createdAt'] is Timestamp
              ? (caseData['createdAt'] as Timestamp).toDate()
              : null;

          final createdAtText = createdAt == null
              ? '-'
              : '${createdAt.day}/${createdAt.month}/${createdAt.year}';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  title: 'Case Summary',
                  children: [
                    _detailRow('Case ID', caseId),
                    _detailRow('Status', caseData['status'] ?? '-'),
                    _detailRow('Created At', createdAtText),
                  ],
                ),
                const SizedBox(height: 16),

                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(ownerId)
                      .get(),
                  builder: (context, userSnap) {
                    final userData = userSnap.hasData && userSnap.data!.exists
                        ? userSnap.data!.data() as Map<String, dynamic>
                        : <String, dynamic>{};

                    return _sectionCard(
                      title: 'User Information',
                      children: [
                        _detailRow('Name', userData['name'] ?? '-'),
                        _detailRow(
                          'National ID',
                          userData['nationalID'] ?? '-',
                        ),
                        _detailRow('Phone', userData['phoneNumber'] ?? '-'),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('vehicles')
                      .doc(vehicleId)
                      .get(),
                  builder: (context, vehicleSnap) {
                    final vehicleData =
                        vehicleSnap.hasData && vehicleSnap.data!.exists
                        ? vehicleSnap.data!.data() as Map<String, dynamic>
                        : <String, dynamic>{};

                    return _sectionCard(
                      title: 'Vehicle Information',
                      children: [
                        _detailRow('Make', vehicleData['make'] ?? '-'),
                        _detailRow('Model', vehicleData['model'] ?? '-'),
                        _detailRow(
                          'Plate Number',
                          vehicleData['plateNumber'] ?? '-',
                        ),
                        _detailRow('Year', vehicleData['year'] ?? '-'),
                        _detailRow('Color', vehicleData['color'] ?? '-'),
                        _detailRow(
                          'Chassis Number',
                          vehicleData['chassisNumber'] ?? '-',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                _sectionCard(
                  title: 'Najm Report',
                  children: [
                    _detailRow(
                      'Accident Number',
                      najmReport['accidentNumber'] ?? '-',
                    ),
                    _detailRow(
                      'Accident Date',
                      najmReport['accidentDate'] ?? '-',
                    ),
                    _detailRow(
                      'Damage Location',
                      najmReport['damageLocation'] ?? '-',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _imagesSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardGrey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    final displayValue = value == null || value.toString().trim().isEmpty
        ? '-'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                fontSize: 13.5,
                color: _textDark,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagesSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(caseId)
          .collection('images')
          .orderBy('uploadedAt')
          .snapshots(),
      builder: (context, imageSnap) {
        if (imageSnap.connectionState == ConnectionState.waiting) {
          return _sectionCard(
            title: 'Damage Images',
            children: const [Center(child: CircularProgressIndicator())],
          );
        }

        final images = imageSnap.data?.docs ?? [];

        if (images.isEmpty) {
          return _sectionCard(
            title: 'Damage Images',
            children: const [
              Text(
                'No images uploaded.',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        }

        return _sectionCard(
          title: 'Damage Images',
          children: [
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final data = images[index].data() as Map<String, dynamic>;
                  final url = data['downloadUrl'] ?? '';

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: Colors.white,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: _blue,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
