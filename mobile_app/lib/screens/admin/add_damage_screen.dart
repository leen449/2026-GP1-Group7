import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AddDamageScreen extends StatefulWidget {
  final String caseId;

  const AddDamageScreen({super.key, required this.caseId});

  @override
  State<AddDamageScreen> createState() => _AddDamageScreenState();
}

class _AddDamageScreenState extends State<AddDamageScreen> {
  static const Color primaryBlue = Color(0xFF173F7A);
  static const Color borderColor = Color(0xFFD7E0EC);

  // Backend base URL used to submit the admin-added damage.
  static const String backendUrl = 'http://172.20.10.2:8000';

  // Controls the current step:
  // 0 = image selection, 1 = damage details, 2 = review.
  int _currentStep = 0;

  bool _isLoadingImages = true;
  bool _isSubmitting = false;

  List<CaseImage> _images = [];

  CaseImage? _selectedImage;

  String? _selectedDamageType;
  String? _selectedPart;
  String? _selectedSeverity;

  // These values should match the values expected by the backend.
  final List<DropdownOption> _damageTypes = const [
    DropdownOption(value: 'dent', label: 'انبعاج', englishLabel: 'Dent'),
    DropdownOption(value: 'scratch', label: 'خدش', englishLabel: 'Scratch'),
    DropdownOption(value: 'crack', label: 'تشقق', englishLabel: 'Crack'),
    DropdownOption(value: 'glass', label: 'كسر الزجاج', englishLabel: 'Glass'),
    DropdownOption(value: 'lamp', label: 'كسر المصباح', englishLabel: 'Lamp'),
    DropdownOption(
      value: 'tire_flat',
      label: 'إطار تالف',
      englishLabel: 'Tire Flat',
    ),
  ];

  final List<DropdownOption> _parts = const [
    DropdownOption(
      value: 'front_bumper',
      label: 'الصدام الأمامي',
      englishLabel: 'Front Bumper',
    ),
    DropdownOption(
      value: 'rear_bumper',
      label: 'الصدام الخلفي',
      englishLabel: 'Rear Bumper',
    ),
    DropdownOption(value: 'hood', label: 'غطاء المحرك', englishLabel: 'Hood'),
    DropdownOption(
      value: 'trunk',
      label: 'الصندوق الخلفي',
      englishLabel: 'Trunk',
    ),
    DropdownOption(
      value: 'front_left_door',
      label: 'الباب الأمامي الأيسر',
      englishLabel: 'Front Left Door',
    ),
    DropdownOption(
      value: 'front_right_door',
      label: 'الباب الأمامي الأيمن',
      englishLabel: 'Front Right Door',
    ),
    DropdownOption(
      value: 'back_left_door',
      label: 'الباب الخلفي الأيسر',
      englishLabel: 'Back Left Door',
    ),
    DropdownOption(
      value: 'back_right_door',
      label: 'الباب الخلفي الأيمن',
      englishLabel: 'Back Right Door',
    ),
    DropdownOption(
      value: 'front_fender',
      label: 'الرفرف الأمامي',
      englishLabel: 'Front Fender',
    ),
    DropdownOption(
      value: 'rear_fender',
      label: 'الرفرف الخلفي',
      englishLabel: 'Rear Fender',
    ),
    DropdownOption(value: 'roof', label: 'السقف', englishLabel: 'Roof'),
    DropdownOption(
      value: 'windshield',
      label: 'الزجاج الأمامي',
      englishLabel: 'Windshield',
    ),
    DropdownOption(value: 'lamp', label: 'المصباح', englishLabel: 'Lamp'),
    DropdownOption(value: 'wheel', label: 'الإطار', englishLabel: 'Wheel'),
  ];

  final List<DropdownOption> _severities = const [
    DropdownOption(value: 'minor', label: 'خفيف', englishLabel: 'Minor'),
    DropdownOption(
      value: 'moderate',
      label: 'متوسط',
      englishLabel: 'Moderate',
    ),
    DropdownOption(value: 'severe', label: 'شديد', englishLabel: 'Severe'),
  ];

  @override
  void initState() {
    super.initState();

    // Load all images that belong to this accident case.
    _loadCaseImages();
  }

  Future<void> _loadCaseImages() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('accidentCase')
          .doc(widget.caseId)
          .collection('images')
          .get();

      // Convert Firestore image documents into local CaseImage objects.
      final images = snapshot.docs
          .map((doc) {
            final data = doc.data();

            return CaseImage(
              id: doc.id,
              downloadUrl: data['downloadUrl']?.toString() ?? '',
              label: data['label']?.toString() ?? '',
            );
          })
          .where((image) {
            return image.downloadUrl.isNotEmpty;
          })
          .toList();

      if (!mounted) return;

      setState(() {
        _images = images;
        _isLoadingImages = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingImages = false;
      });

      _showErrorDialog('تعذر تحميل صور الحالة. يرجى المحاولة مرة أخرى.');
    }
  }

  void _goToDetails() {
    if (_selectedImage == null) {
      _showMessage('يرجى اختيار صورة أولاً.');
      return;
    }

    setState(() {
      _currentStep = 1;
    });
  }

  void _goToReview() {
    // Prevent moving to review before completing all required fields.
    if (_selectedDamageType == null ||
        _selectedPart == null ||
        _selectedSeverity == null) {
      _showMessage('يرجى إكمال جميع بيانات الضرر.');
      return;
    }

    setState(() {
      _currentStep = 2;
    });
  }

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _currentStep--;
    });
  }

  Future<void> _submitDamage() async {
    if (_selectedImage == null ||
        _selectedDamageType == null ||
        _selectedPart == null ||
        _selectedSeverity == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // The selected image ID is sent so the backend knows
      // under which image the new costItem should be stored.
      final uri = Uri.parse('$backendUrl/admin/cases/${widget.caseId}/damages');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageId': _selectedImage!.id,
          'damageType': _selectedDamageType,
          'part': _selectedPart,
          'severity': _selectedSeverity,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;

        _showSuccessDialog();
      } else {
        String message = 'تعذر إضافة الضرر.';

        try {
          final body = jsonDecode(response.body);

          if (body is Map && body['detail'] != null) {
            message = body['detail'].toString();
          }
        } catch (_) {}

        if (!mounted) return;

        _showErrorDialog(message);
      }
    } catch (e) {
      if (!mounted) return;

      _showErrorDialog('حدث خطأ أثناء إضافة الضرر. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _resetForm() {
    Navigator.of(context).pop();

    // Reset all selections so the admin can add another damage.
    setState(() {
      _currentStep = 0;
      _selectedImage = null;
      _selectedDamageType = null;
      _selectedPart = null;
      _selectedSeverity = null;
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFE1F7EF),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 42,
                    color: Color(0xFF07966D),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'تمت إضافة الضرر بنجاح',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF142A4A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'تمت إضافة الضرر إلى الصورة ${_imageNumber(_selectedImage!)} وسيتم تحديث التكلفة تلقائيًا.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    height: 1.7,
                    fontSize: 14,
                    color: Color(0xFF68758A),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _resetForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'إضافة ضرر آخر',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);

                      // Return true so the previous screen can refresh its data.
                      Navigator.pop(context, true);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryBlue,
                      side: const BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'العودة إلى تفاصيل الحالة',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red),
                SizedBox(width: 8),
                Text('تعذر إضافة الضرر'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('حسنًا'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textAlign: TextAlign.right)),
    );
  }

  String _imageNumber(CaseImage image) {
    final index = _images.indexWhere((item) => item.id == image.id);

    return '${index + 1}';
  }

  DropdownOption? _findOption(List<DropdownOption> options, String? value) {
    if (value == null) return null;

    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'إضافة ضرر',
            style: TextStyle(
              color: Color(0xFF142A4A),
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          leading: IconButton(
            onPressed: _goBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF142A4A),
              size: 21,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildStepIndicator(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildCurrentStep(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildImageSelectionStep();

      case 1:
        return _buildDamageDetailsStep();

      case 2:
        return _buildReviewStep();

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Row(
        children: [
          _buildStep(index: 0, label: 'اختيار الصورة'),
          _buildStepLine(0),
          _buildStep(index: 1, label: 'تفاصيل الضرر'),
          _buildStepLine(1),
          _buildStep(index: 2, label: 'مراجعة'),
        ],
      ),
    );
  }

  Widget _buildStep({required int index, required String label}) {
    final bool completed = index < _currentStep;
    final bool active = index == _currentStep;

    return Expanded(
      flex: 2,
      child: Column(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: completed || active ? primaryBlue : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: completed || active
                    ? primaryBlue
                    : const Color(0xFFB7C5D9),
                width: 1.5,
              ),
            ),
            child: Center(
              child: completed
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFF8997AA),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active || completed
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: active || completed
                  ? const Color(0xFF142A4A)
                  : const Color(0xFF8997AA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int index) {
    final completed = index < _currentStep;

    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 28),
        color: completed ? primaryBlue : const Color(0xFFD7E0EC),
      ),
    );
  }

  Widget _buildImageSelectionStep() {
    return Padding(
      key: const ValueKey('imageStep'),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'في أي صورة يظهر الضرر الذي تريد إضافته؟',
            style: TextStyle(
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF142A4A),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'اختر الصورة التي يظهر فيها الضرر بشكل أوضح.',
            style: TextStyle(fontSize: 14, color: Color(0xFF738096)),
          ),
          const SizedBox(height: 24),

          Expanded(child: _buildImagesGrid()),

          _primaryButton(text: 'التالي', onPressed: _goToDetails),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildImagesGrid() {
    if (_isLoadingImages) {
      return const Center(child: CircularProgressIndicator(color: primaryBlue));
    }

    if (_images.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد صور لهذه الحالة.',
          style: TextStyle(color: Color(0xFF738096)),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: _images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, index) {
        final image = _images[index];

        return _buildImageItem(image: image, number: index + 1);
      },
    );
  }

  Widget _buildImageItem({required CaseImage image, required int number}) {
    final bool selected = _selectedImage?.id == image.id;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        // Save the selected Firestore image document.
        setState(() {
          _selectedImage = image;
        });
      },
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected ? const Color(0xFF2563EB) : borderColor,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(selected ? 10 : 12),
                    child: Image.network(
                      image.downloadUrl,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFFF2F4F8),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                if (selected)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF2563EB),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF9CACBF),
              ),
              const SizedBox(width: 5),
              Text(
                'الصورة $number',
                style: const TextStyle(fontSize: 13, color: Color(0xFF2C3D57)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDamageDetailsStep() {
    return SingleChildScrollView(
      key: const ValueKey('detailsStep'),
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSelectedImageCard(),

          const SizedBox(height: 26),

          _buildDropdown(
            title: 'نوع الضرر',
            hint: 'اختر نوع الضرر',
            value: _selectedDamageType,
            options: _damageTypes,
            onChanged: (value) {
              setState(() {
                _selectedDamageType = value;
              });
            },
          ),

          const SizedBox(height: 20),

          _buildDropdown(
            title: 'الجزء المتضرر',
            hint: 'اختر الجزء المتضرر',
            value: _selectedPart,
            options: _parts,
            onChanged: (value) {
              setState(() {
                _selectedPart = value;
              });
            },
          ),

          const SizedBox(height: 20),

          _buildDropdown(
            title: 'الشدة',
            hint: 'اختر شدة الضرر',
            value: _selectedSeverity,
            options: _severities,
            onChanged: (value) {
              setState(() {
                _selectedSeverity = value;
              });
            },
          ),

          const SizedBox(height: 22),

          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 21, color: Color(0xFF2563EB)),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'سيتم حساب تكلفة الضرر تلقائيًا بناءً على نوع الضرر والجزء المتضرر والشدة.',
                    style: TextStyle(
                      height: 1.7,
                      fontSize: 13,
                      color: Color(0xFF54719B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: _secondaryButton(text: 'السابق', onPressed: _goBack),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _primaryButton(text: 'التالي', onPressed: _goToReview),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImageCard() {
    if (_selectedImage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.network(
              _selectedImage!.downloadUrl,
              width: 92,
              height: 76,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الصورة المحددة',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8997AA)),
                ),
                const SizedBox(height: 4),
                Text(
                  'الصورة ${_imageNumber(_selectedImage!)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF142A4A),
                  ),
                ),
                const SizedBox(height: 7),
                InkWell(
                  onTap: () {
                    // Return to step 1 without clearing the other selections.
                    setState(() {
                      _currentStep = 0;
                    });
                  },
                  child: const Text(
                    'تغيير الصورة',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String title,
    required String hint,
    required String? value,
    required List<DropdownOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF142A4A),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 1.6,
              ),
            ),
          ),
          hint: Text(
            hint,
            style: const TextStyle(color: Color(0xFF99A5B5), fontSize: 14),
          ),
          items: options.map((option) {
            return DropdownMenuItem<String>(
              value: option.value,
              child: Text(
                '${option.label} (${option.englishLabel})',
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    // Convert stored backend values back to readable labels for the review screen.
    final damage = _findOption(_damageTypes, _selectedDamageType);

    final part = _findOption(_parts, _selectedPart);

    final severity = _findOption(_severities, _selectedSeverity);

    return SingleChildScrollView(
      key: const ValueKey('reviewStep'),
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'مراجعة الضرر الجديد',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF142A4A),
            ),
          ),

          const SizedBox(height: 18),

          Container(
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                if (_selectedImage != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: Image.network(
                      _selectedImage!.downloadUrl,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _reviewRow(
                        'الصورة المحددة',
                        'الصورة ${_imageNumber(_selectedImage!)}',
                      ),
                      const Divider(height: 25),
                      _reviewRow(
                        'نوع الضرر',
                        damage == null
                            ? '-'
                            : '${damage.label} (${damage.englishLabel})',
                      ),
                      const Divider(height: 25),
                      _reviewRow(
                        'الجزء المتضرر',
                        part == null
                            ? '-'
                            : '${part.label} (${part.englishLabel})',
                      ),
                      const Divider(height: 25),
                      _reviewRow(
                        'الشدة',
                        severity == null
                            ? '-'
                            : '${severity.label} (${severity.englishLabel})',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.calculate_outlined, color: Color(0xFF2563EB)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'سيتم حساب التكلفة وتحديث إجمالي الحالة تلقائيًا بعد إضافة الضرر.',
                    style: TextStyle(color: Color(0xFF54719B), height: 1.6),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: _secondaryButton(
                  text: 'السابق',
                  onPressed: _isSubmitting ? null : _goBack,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _primaryButton(
                  text: _isSubmitting ? 'جاري الإضافة...' : 'إضافة الضرر',
                  onPressed: _isSubmitting ? null : _submitDamage,
                  loading: _isSubmitting,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, color: Color(0xFF7E8B9D)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF142A4A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String text,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      height: 53,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primaryBlue,
          disabledBackgroundColor: primaryBlue.withOpacity(0.55),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _secondaryButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 53,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          side: const BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// Represents one image document stored under accidentCase/{caseId}/images.
class CaseImage {
  final String id;
  final String downloadUrl;
  final String label;

  const CaseImage({
    required this.id,
    required this.downloadUrl,
    required this.label,
  });
}

// Keeps the backend value separate from the Arabic UI label.
class DropdownOption {
  final String value;
  final String label;
  final String englishLabel;

  const DropdownOption({
    required this.value,
    required this.label,
    required this.englishLabel,
  });
}
