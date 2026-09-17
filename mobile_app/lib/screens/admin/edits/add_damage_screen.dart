import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AddDamageScreen extends StatefulWidget {
  final String caseId;
  final String imageId;
  final String imageUrl;
  final int imageNumber;
  final bool isObjectionFlow;

  const AddDamageScreen({
    super.key,
    required this.caseId,
    required this.imageId,
    required this.imageUrl,
    required this.imageNumber,
    this.isObjectionFlow = false,
  });

  @override
  State<AddDamageScreen> createState() => _AddDamageScreenState();
}

class _AddDamageScreenState extends State<AddDamageScreen> {
  static const Color primaryBlue = Color(0xFF173F7A);
  static const Color borderColor = Color(0xFFD7E0EC);

  // Backend base URL used to submit the admin-added damage.
  static const String backendUrl = 'http://192.168.0.239:8000';

  // Controls the current step:
  // 0 = damage details
  // 1 = review
  int _currentStep = 0;

  bool _isSubmitting = false;

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
      value: 'tire',
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
      value: 'back_bumper',
      label: 'الصدام الخلفي',
      englishLabel: 'Back Bumper',
    ),
    DropdownOption(value: 'door', label: 'الباب', englishLabel: 'Door'),
    DropdownOption(value: 'fender', label: 'الرفرف', englishLabel: 'Fender'),
    DropdownOption(value: 'hood', label: 'غطاء المحرك', englishLabel: 'Hood'),
    DropdownOption(
      value: 'trunk',
      label: 'الصندوق الخلفي',
      englishLabel: 'Trunk',
    ),
    DropdownOption(value: 'roof', label: 'السقف', englishLabel: 'Roof'),
    DropdownOption(
      value: 'sill',
      label: 'العتبة الجانبية',
      englishLabel: 'Sill',
    ),
    DropdownOption(
      value: 'windshield',
      label: 'الزجاج',
      englishLabel: 'Windshield',
    ),
    DropdownOption(value: 'lamp', label: 'المصباح', englishLabel: 'Lamp'),
    DropdownOption(value: 'wheel', label: 'الإطار', englishLabel: 'Wheel'),
  ];

  final List<DropdownOption> _severities = const [
    DropdownOption(value: 'minor', label: 'خفيف', englishLabel: 'Minor'),
    DropdownOption(value: 'moderate', label: 'متوسط', englishLabel: 'Moderate'),
    DropdownOption(value: 'severe', label: 'شديد', englishLabel: 'Severe'),
  ];

  void _goToReview() {
    // Prevent moving to review before completing all required fields.
    if (_selectedDamageType == null ||
        _selectedPart == null ||
        _selectedSeverity == null) {
      _showMessage('يرجى إكمال جميع بيانات الضرر.');
      return;
    }

    setState(() {
      _currentStep = 1;
    });
  }

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _currentStep = 0;
    });
  }

  Future<void> _submitDamage() async {
    if (_selectedDamageType == null ||
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
      final uri = Uri.parse(
        '$backendUrl/damage/admin/cases/${widget.caseId}/damages',
      );

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageId': widget.imageId,
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

  void _handleAddAnotherDamage(BuildContext dialogContext) {
    // Close the success dialog.
    Navigator.pop(dialogContext);

    if (widget.isObjectionFlow) {
      // Close AddDamageScreen.
      Navigator.pop(context, true);

      // Close EditDamagesScreen and return to image selection.
      Navigator.pop(context, true);
      return;
    }

    // In the normal review flow, stay on the same image
    // and reset the form to add another damage.
    setState(() {
      _currentStep = 0;
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
                  'تمت إضافة الضرر إلى الصورة ${widget.imageNumber} وسيتم تحديث التكلفة تلقائيًا.',
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
                    onPressed: () {
                      _handleAddAnotherDamage(dialogContext);
                    },
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
                      // Close the success dialog.
                      Navigator.pop(dialogContext);

                      // Close AddDamageScreen.
                      Navigator.pop(context, true);

                      // Close EditDamagesScreen.
                      Navigator.pop(context, true);

                      if (widget.isObjectionFlow) {
                        // Close image selection and return to objection details.
                        Navigator.pop(context, true);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
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
          automaticallyImplyLeading: false,
          leading: _currentStep == 1
              ? IconButton(
                  onPressed: _goBack,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFF142A4A),
                    size: 21,
                  ),
                )
              : null,
          title: const Text(
            'إضافة ضرر',
            style: TextStyle(
              color: Color(0xFF142A4A),
              fontWeight: FontWeight.bold,
              fontSize: 19,
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
        return _buildDamageDetailsStep();

      case 1:
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
          _buildStep(index: 0, label: 'تفاصيل الضرر'),
          _buildStepLine(0),
          _buildStep(index: 1, label: 'مراجعة'),
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
                flex: 2,
                child: _primaryButton(text: 'التالي', onPressed: _goToReview),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _secondaryButton(
                  text: 'إلغاء',
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImageCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Show a portrait preview so the complete image remains visible.
          Container(
            width: 85,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.network(
                widget.imageUrl,
                width: 85,
                height: 120,

                // Keep the full image visible without cropping.
                fit: BoxFit.contain,

                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'الصورة المحددة',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8997AA)),
                ),

                const SizedBox(height: 4),

                Text(
                  'الصورة ${widget.imageNumber}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF142A4A),
                  ),
                ),

                const SizedBox(height: 7),
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
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF142A4A),
          ),
        ),

        const SizedBox(height: 8),

        Directionality(
          textDirection: TextDirection.rtl,
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,

            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF68758A),
            ),

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

            hint: Align(
              alignment: Alignment.centerRight,
              child: Text(
                hint,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Color(0xFF99A5B5), fontSize: 14),
              ),
            ),

            // Keep the selected value aligned to the right.
            selectedItemBuilder: (context) {
              return options.map((option) {
                return Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    option.label,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF142A4A),
                    ),
                  ),
                );
              }).toList();
            },

            // Show Arabic labels only inside the dropdown menu.
            items: options.map((option) {
              return DropdownMenuItem<String>(
                value: option.value,
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    option.label,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF142A4A),
                    ),
                  ),
                ),
              );
            }).toList(),

            onChanged: onChanged,
          ),
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
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: Image.network(
                      widget.imageUrl,
                      width: double.infinity,
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 42,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _reviewRow(
                        'الصورة المحددة',
                        'الصورة ${widget.imageNumber}',
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
                flex: 2,
                child: _primaryButton(
                  text: _isSubmitting ? 'جاري الإضافة...' : 'إضافة الضرر',
                  onPressed: _isSubmitting ? null : _submitDamage,
                  loading: _isSubmitting,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _secondaryButton(
                  text: 'إلغاء',
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          final navigator = Navigator.of(context);

                          // Close AddDamageScreen.
                          navigator.pop();

                          // Close EditDamagesScreen and return to case details.
                          navigator.pop();
                        },
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
