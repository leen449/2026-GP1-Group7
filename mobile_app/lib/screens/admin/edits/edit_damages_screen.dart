import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'edit_single_damage_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'add_damage_screen.dart';

class EditDamagesScreen extends StatelessWidget {
  final String caseId;
  final String imageId;
  final String imageUrl;
  final int imageNumber;
  final bool isObjectionFlow;

  const EditDamagesScreen({
    super.key,
    required this.caseId,
    required this.imageId,
    required this.imageUrl,
    required this.imageNumber,
    this.isObjectionFlow = false,
  });

  static const Color primaryBlue = Color(0xFF173F7A);
  static const Color borderColor = Color(0xFFD7E0EC);
  static const Color textDark = Color(0xFF142A4A);
  // Matches the app's established button language (see _primaryBlue /
  // _confirmDialog in Case_Details_Screen.dart, admin_case_review_screen.dart)
  // — the buttons below previously used primaryBlue above (and, in one case,
  // a border color that didn't even match it), neither consistent with the
  // rest of the app's buttons.
  static const Color buttonPrimary = Color(0xFF1E3A6E);
  static const Color buttonSecondary = Color(0xFFEDEDED);
  static const Color buttonDanger = Color(0xFFDC2626);

  static const String backendUrl = 'http://192.168.0.13:8000';

  static const Map<String, String> damageLabels = {
    'dent': 'انبعاج',
    'scratch': 'خدش',
    'crack': 'تشقق',
    'glass': 'كسر زجاج',
    'lamp': 'كسر مصباح',
    'tire': 'ضرر إطار',
  };

  static const Map<String, String> partLabels = {
    'door': 'الباب',
    'front_bumper': 'الصدام الأمامي',
    'back_bumper': 'الصدام الخلفي',
    'fender': 'الرفرف',
    'hood': 'غطاء المحرك',
    'trunk': 'الصندوق الخلفي',
    'roof': 'السقف',
    'sill': 'العتبة الجانبية',
    'windshield': 'الزجاج',
    'lamp': 'المصباح',
    'wheel': 'الإطار',
  };

  static const Map<String, String> severityLabels = {
    'minor': 'ضرر بسيط',
    'moderate': 'ضرر متوسط',
    'severe': 'ضرر شديد',
  };

  @override
  Widget build(BuildContext context) {
    final itemsRef = FirebaseFirestore.instance
        .collection('accidentCase')
        .doc(caseId)
        .collection('images')
        .doc(imageId)
        .collection('costItems');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'تعديل أضرار الصورة',
            style: TextStyle(
              color: textDark,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark),
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: itemsRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: primaryBlue),
              );
            }

            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل الأضرار.'));
            }

            // Soft-deleted items (removedByAdmin) stay in Firestore for
            // audit on the review pages, but must not appear as still-active
            // here — otherwise they'd double count against the case total,
            // which already excludes them server-side (see
            // _recalculate_admin_totals in cost_estimation_services.py).
            final docs = (snapshot.data?.docs ?? [])
                .where((doc) => doc.data()['removedByAdmin'] != true)
                .toList();

            double imageTotal = 0;

            for (final doc in docs) {
              final data = doc.data();
              final cost = data['lineCostSar'];

              if (cost is num) {
                imageTotal += cost.toDouble();
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildImageHeader(imageTotal),

                  const SizedBox(height: 24),

                  const Text(
                    'الأضرار في هذه الصورة',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (docs.isEmpty)
                    _buildEmptyState()
                  else
                    ...docs.map((doc) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _buildDamageCard(
                          context,
                          itemId: doc.id,
                          data: doc.data(),
                        ),
                      );
                    }),

                  const SizedBox(height: 8),

                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      //open AddDamageScreen with this image preselected.
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddDamageScreen(
                              caseId: caseId,
                              imageId: imageId,
                              imageUrl: imageUrl,
                              imageNumber: imageNumber,
                              isObjectionFlow: isObjectionFlow,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'إضافة ضرر جديد لهذه الصورة',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F7FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 21,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'يمكنك تعديل أو حذف أي ضرر في هذه الصورة، وسيتم تحديث التكلفة تلقائيًا.',
                            style: TextStyle(
                              color: Color(0xFF54719B),
                              fontSize: 13,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildImageHeader(double total) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 90,
                      height: 90,
                      color: const Color(0xFFF2F4F8),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الصورة $imageNumber',
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'إجمالي تكلفة الصورة',
                      style: TextStyle(color: Color(0xFF8997AA), fontSize: 13),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '${total.toStringAsFixed(2)} ريال',
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDamageCard(
    BuildContext context, {
    required String itemId,
    required Map<String, dynamic> data,
  }) {
    final damageType = data['damageType']?.toString() ?? '';
    final part = data['part']?.toString() ?? '';
    final severity = data['severity']?.toString();
    final lineCost = data['lineCostSar'];

    final damageLabel = damageLabels[damageType] ?? damageType;
    final partLabel = partLabels[part] ?? part;
    final severityLabel = severityLabels[severity] ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (severityLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    severityLabel,
                    style: const TextStyle(
                      color: Color(0xFFE58A00),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              const Spacer(),

              IconButton(
                tooltip: 'تعديل الضرر',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditSingleDamageScreen(
                        caseId: caseId,
                        imageId: imageId,
                        itemId: itemId,
                        imageUrl: imageUrl,
                        imageNumber: imageNumber,
                        damageType: damageType,
                        part: part,
                        severity: severity ?? 'moderate',
                        lineCostSar: lineCost is num
                            ? lineCost.toDouble()
                            : null,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF2563EB)),
              ),

              IconButton(
                tooltip: 'حذف الضرر',
                onPressed: () {
                  _showDeleteConfirmation(context, itemId: itemId);
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            partLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: textDark,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            damageLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF68758A), fontSize: 14),
          ),

          const SizedBox(height: 15),

          const Divider(height: 1),

          const SizedBox(height: 13),

          Row(
            children: [
              const Text(
                'التكلفة',
                style: TextStyle(color: Color(0xFF8997AA), fontSize: 13),
              ),

              const Spacer(),

              Text(
                lineCost is num ? '${lineCost.toStringAsFixed(2)} ريال' : '-',
                style: const TextStyle(
                  color: textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: const Column(
        children: [
          Icon(Icons.description_outlined, size: 42, color: Color(0xFF9CACBF)),
          SizedBox(height: 12),
          Text(
            'لا توجد أضرار في هذه الصورة.',
            style: TextStyle(color: Color(0xFF68758A), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context, {
    required String itemId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            contentPadding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD6D6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_outlined,
                    color: Color(0xFFFF2E2E),
                    size: 44,
                  ),
                ),

                const SizedBox(height: 18),

                const Text(
                  'حذف الضرر',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'هل أنت متأكد من حذف هذا الضرر؟',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF5F718A),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonDanger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'حذف',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonSecondary,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && context.mounted) {
      await _deleteDamage(context, itemId);
    }
  }

  Future<void> _deleteDamage(BuildContext context, String itemId) async {
    try {
      final uri = Uri.parse(
        '$backendUrl/damage/admin/cases/'
        '$caseId/images/'
        '$imageId/cost-items/'
        '$itemId',
      );

      final response = await http.delete(uri);

      if (!context.mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الضرر بنجاح', textAlign: TextAlign.right),
          ),
        );

        return;
      }

      String message = 'تعذر حذف الضرر.';

      try {
        final body = jsonDecode(response.body);

        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, textAlign: TextAlign.right)),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء حذف الضرر.', textAlign: TextAlign.right),
        ),
      );
    }
  }
}
