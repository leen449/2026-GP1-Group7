import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'edit_damages_screen.dart';

class ObjectionCaseEditScreen extends StatefulWidget {
  final String caseId;

  const ObjectionCaseEditScreen({
    super.key,
    required this.caseId,
  });

  @override
  State<ObjectionCaseEditScreen> createState() =>
      _ObjectionCaseEditScreenState();
}

class _ObjectionCaseEditScreenState extends State<ObjectionCaseEditScreen> {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color darkBlue = Color(0xFF173F7A);
  static const Color textDark = Color(0xFF142A4A);
  static const Color borderColor = Color(0xFFD7E0EC);
  static const Color pageBg = Color(0xFFF7FAFF);
  // Matches the app's established primary-button color (see _primaryBlue in
  // Case_Details_Screen.dart / admin_case_review_screen.dart) — the "التالي"
  // button below previously used darkBlue, which doesn't match it.
  static const Color buttonPrimary = Color(0xFF1E3A6E);

  String? _selectedImageId;
  String? _selectedImageUrl;
  int? _selectedImageNumber;

  void _selectImage({
    required String imageId,
    required String imageUrl,
    required int imageNumber,
  }) {
    setState(() {
      _selectedImageId = imageId;
      _selectedImageUrl = imageUrl;
      _selectedImageNumber = imageNumber;
    });
  }

  void _goNext() {
    if (_selectedImageId == null ||
        _selectedImageUrl == null ||
        _selectedImageNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى اختيار صورة أولاً',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditDamagesScreen(
          caseId: widget.caseId,
          imageId: _selectedImageId!,
          imageUrl: _selectedImageUrl!,
          imageNumber: _selectedImageNumber!,
          isObjectionFlow: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'تعديل الحالة',
            style: TextStyle(
              color: textDark,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: textDark,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('accidentCase')
              .doc(widget.caseId)
              .collection('images')
              .orderBy('uploadedAt')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: primaryBlue,
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'حدث خطأ أثناء تحميل الصور',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 14,
                  ),
                ),
              );
            }

            final images = snapshot.data?.docs ?? [];

            if (images.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد صور لهذه الحالة',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 14,
                  ),
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      24,
                      20,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'اختر الصورة التي تريد تعديل أضرارها',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: textDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'اختر صورة لمراجعة أضرارها أو تعديلها أو إضافة ضرر جديد.',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Color(0xFF7A8798),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 24),

                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: images.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemBuilder: (context, index) {
                            final imageDoc = images[index];

                            final data =
                                imageDoc.data() as Map<String, dynamic>;

                            final String imageUrl =
                                data['downloadUrl']?.toString() ?? '';

                            final int imageNumber = index + 1;

                            return _imageCard(
                              imageId: imageDoc.id,
                              imageUrl: imageUrl,
                              imageNumber: imageNumber,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    20,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: Color(0xFFE8EEF7),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'التالي',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _imageCard({
    required String imageId,
    required String imageUrl,
    required int imageNumber,
  }) {
    final bool isSelected = _selectedImageId == imageId;

    return Center(
      child: SizedBox(
        width: 155,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            _selectImage(
              imageId: imageId,
              imageUrl: imageUrl,
              imageNumber: imageNumber,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? primaryBlue : borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: imageUrl.isEmpty
                        ? Container(
                            color: const Color(0xFFEAF2FF),
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: darkBlue,
                                size: 32,
                              ),
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return Container(
                                color: const Color(0xFFEAF2FF),
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: darkBlue,
                                    size: 32,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        'الصورة $imageNumber',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: Radio<String>(
                          value: imageId,
                          groupValue: _selectedImageId,
                          activeColor: primaryBlue,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) {
                            _selectImage(
                              imageId: imageId,
                              imageUrl: imageUrl,
                              imageNumber: imageNumber,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}