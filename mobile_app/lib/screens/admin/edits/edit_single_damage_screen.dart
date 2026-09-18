import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class EditSingleDamageScreen extends StatefulWidget {
  final String caseId;
  final String imageId;
  final String itemId;
  final String imageUrl;
  final int imageNumber;

  final String damageType;
  final String part;
  final String severity;
  final double? lineCostSar;

  const EditSingleDamageScreen({
    super.key,
    required this.caseId,
    required this.imageId,
    required this.itemId,
    required this.imageUrl,
    required this.imageNumber,
    required this.damageType,
    required this.part,
    required this.severity,
    required this.lineCostSar,
  });

  @override
  State<EditSingleDamageScreen> createState() => _EditSingleDamageScreenState();
}

class _EditSingleDamageScreenState extends State<EditSingleDamageScreen> {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color darkBlue = Color(0xFF173F7A);
  static const Color textDark = Color(0xFF142A4A);
  static const Color borderColor = Color(0xFFD7E0EC);
  static const Color pageBg = Color(0xFFF7FAFF);
  // Matches the app's established button language (see _primaryBlue /
  // _confirmDialog in Case_Details_Screen.dart, admin_case_review_screen.dart)
  // — buttons on this screen previously used darkBlue/primaryBlue above,
  // neither of which matches the rest of the app's buttons.
  static const Color buttonPrimary = Color(0xFF1E3A6E);
  static const Color buttonSecondary = Color(0xFFEDEDED);

  static const String backendUrl = 'http://192.168.0.13:8000';

  late String _selectedDamageType;
  late String _selectedPart;
  late String _selectedSeverity;

  bool _isSaving = false;

  final Map<String, String> _damageLabels = const {
    'dent': 'انبعاج',
    'scratch': 'خدش',
    'crack': 'تشقق',
    'glass': 'كسر زجاج',
    'lamp': 'كسر مصباح',
    'tire': 'ضرر إطار',
  };

  final Map<String, String> _partLabels = const {
    'door': 'الباب',
    'front_bumper': 'الصدام الأمامي',
    'back_bumper': 'الصدام الخلفي',
    'fender': 'الرفرف',
    'hood': 'غطاء المحرك',
    'trunk': 'الصندوق الخلفي',
    'roof': 'السقف',
    'sill': 'العتبة الجانبية',
    'windshield': 'الزجاج الأمامي أو الخلفي',
    'door_glass': 'زجاج الباب',
    'lamp': 'المصباح',
    'wheel': 'الإطار',
  };

  final Map<String, String> _severityLabels = const {
    'minor': 'بسيط',
    'moderate': 'متوسط',
    'severe': 'شديد',
  };

  @override
  void initState() {
    super.initState();

    _selectedDamageType = widget.damageType;
    _selectedPart = widget.part;
    _selectedSeverity = widget.severity;
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
            'تعديل الضرر',
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDamageHeader(),

                const SizedBox(height: 26),

                _buildLabel('نوع الضرر'),
                const SizedBox(height: 8),
                _buildDropdown(
                  value: _selectedDamageType,
                  items: _damageLabels,
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _selectedDamageType = value;
                    });
                  },
                ),

                const SizedBox(height: 20),

                _buildLabel('الجزء المتضرر'),
                const SizedBox(height: 8),
                _buildDropdown(
                  value: _selectedPart,
                  items: _partLabels,
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _selectedPart = value;
                    });
                  },
                ),

                const SizedBox(height: 20),

                _buildLabel('درجة الشدة'),
                const SizedBox(height: 8),
                _buildDropdown(
                  value: _selectedSeverity,
                  items: _severityLabels,
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _selectedSeverity = value;
                    });
                  },
                ),

                const SizedBox(height: 24),

                _buildCostCard(),

                const SizedBox(height: 14),

                const Text(
                  'سيتم إعادة حساب التكلفة بعد حفظ التعديلات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8B9BB1),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 32),

                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonPrimary,
                            disabledBackgroundColor: const Color(0xFF93C5FD),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'حفظ التعديلات',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  Navigator.pop(context);
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
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
    );
  }

  Widget _buildDamageHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              widget.imageUrl,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  width: 100,
                  height: 100,
                  color: const Color(0xFFF0F3F7),
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey,
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _partLabels[_selectedPart] ?? _selectedPart,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  _damageLabels[_selectedDamageType] ?? _selectedDamageType,
                  style: const TextStyle(
                    color: Color(0xFF7A8799),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 10),

                _buildSeverityChip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityChip() {
    Color background;
    Color textColor;

    switch (_selectedSeverity) {
      case 'minor':
        background = const Color(0xFFE9F8EE);
        textColor = const Color(0xFF299447);
        break;

      case 'severe':
        background = const Color(0xFFFFE8E8);
        textColor = const Color(0xFFD83434);
        break;

      default:
        background = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE58A00);
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'ضرر ${_severityLabels[_selectedSeverity] ?? ''}',
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: textDark,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    // ClipRect clips the sub-pixel RenderFlex overflow that
    // DropdownButtonFormField's internal layout occasionally produces for
    // some Arabic option widths.
    return ClipRect(
      child: DropdownButtonFormField<String>(
        value: items.containsKey(value) ? value : null,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: darkBlue),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 15,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryBlue, width: 1.5),
          ),
        ),
        items: items.entries.map((entry) {
          return DropdownMenuItem<String>(
            value: entry.key,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                entry.value,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: textDark, fontSize: 15),
              ),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildCostCard() {
    final cost = widget.lineCostSar;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFDCEEFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.attach_money_rounded,
              color: primaryBlue,
              size: 28,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التكلفة التقديرية',
                  style: TextStyle(
                    color: Color(0xFF4D73A8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  cost == null ? '-' : '${cost.toStringAsFixed(2)} ريال',
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final uri = Uri.parse(
        '$backendUrl/damage/admin/cases/'
        '${widget.caseId}/images/'
        '${widget.imageId}/cost-items/'
        '${widget.itemId}',
      );

      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'damageType': _selectedDamageType,
          'part': _selectedPart,
          'severity': _selectedSeverity,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;

        await _showSuccessDialog();
        return;
      }

      String message = 'تعذر حفظ التعديلات.';

      try {
        final body = jsonDecode(response.body);

        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}

      if (!mounted) return;

      _showErrorDialog(message);
    } catch (e) {
      if (!mounted) return;

      _showErrorDialog('حدث خطأ أثناء حفظ التعديلات. يرجى المحاولة مرة أخرى.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // Same responsive shape as add_damage_screen.dart's error dialog: a
  // width-constrained Dialog with an Icon + Expanded(Text) header and a
  // full-width pill button, instead of a plain AlertDialog with a bare
  // TextButton — keeps this dialog visually consistent with the rest of
  // the app's buttons regardless of how long `message` is.
  Future<void> _showErrorDialog(String message) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final double screenWidth = MediaQuery.of(dialogContext).size.width;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: screenWidth > 600 ? 400 : screenWidth * 0.85,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(screenWidth * 0.06),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'تعذر إكمال العملية',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'حسنًا',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDFF7E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF2DBE73),
                    size: 48,
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'تم حفظ التعديلات',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'تم تحديث بيانات الضرر والتكلفة بنجاح.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF61728B),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'العودة إلى أضرار الصورة',
                      style: TextStyle(
                        fontSize: 15,
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
  }
}
