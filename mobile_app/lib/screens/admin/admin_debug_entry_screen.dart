import 'package:flutter/material.dart';

import 'admin_case_review_screen.dart';
import 'admin_claim_details_screen.dart';

// TEMPORARY: delete once the real Cases/Claims list pages and admin nav
// (built separately by another team member) exist. This screen exists only
// so the Case Review and Claim Details screens can be opened directly by ID
// for testing before that real navigation is wired up.
class AdminDebugEntryScreen extends StatefulWidget {
  const AdminDebugEntryScreen({super.key});

  @override
  State<AdminDebugEntryScreen> createState() => _AdminDebugEntryScreenState();
}

class _AdminDebugEntryScreenState extends State<AdminDebugEntryScreen> {
  static const Color _pageBg = Color(0xFFF7FAFF);
  static const Color _textDark = Color(0xFF071A3D);
  static const Color _textMuted = Color(0xFF8B97AA);
  static const Color _primaryBlue = Color(0xFF1E3A6E);

  final TextEditingController _caseIdController = TextEditingController();
  final TextEditingController _objectionIdController = TextEditingController();

  @override
  void dispose() {
    _caseIdController.dispose();
    _objectionIdController.dispose();
    super.dispose();
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _textDark),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _idField({
    required TextEditingController controller,
    required String hint,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          textAlign: TextAlign.right,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primaryBlue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text(buttonLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward_ios_rounded, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'دخول تجريبي للمشرف',
          style: TextStyle(color: _textDark, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'هذه الصفحة مؤقتة لأغراض الاختبار فقط، إلى حين إنشاء صفحات قوائم الحالات والاعتراضات وواجهة تنقل المشرف الفعلية.',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(color: _textMuted, fontSize: 12.5, height: 1.6),
              ),
            ),
            _sectionCard(
              title: 'مراجعة حالة',
              children: [
                _idField(
                  controller: _caseIdController,
                  hint: 'معرّف الحالة (caseId)',
                  buttonLabel: 'فتح مراجعة الحالة',
                  onPressed: () {
                    final id = _caseIdController.text.trim();
                    if (id.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AdminCaseReviewScreen(caseId: id)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'مراجعة اعتراض',
              children: [
                _idField(
                  controller: _objectionIdController,
                  hint: 'معرّف الاعتراض (objectionId)',
                  buttonLabel: 'فتح مراجعة الاعتراض',
                  onPressed: () {
                    final id = _objectionIdController.text.trim();
                    if (id.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AdminClaimDetailsScreen(objectionId: id)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
