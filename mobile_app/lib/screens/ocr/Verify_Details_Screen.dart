import 'package:flutter/material.dart';

/// VerifyDetailsScreen
/// This screen allows the user to review and edit vehicle details
/// after the system reads them from the registration card image.
class VerifyDetailsScreen extends StatefulWidget {
  // Path of the captured image (will be used later for OCR processing)
  final String imagePath;

  const VerifyDetailsScreen({super.key, required this.imagePath});

  @override
  State<VerifyDetailsScreen> createState() => _VerifyDetailsScreenState();
}

class _VerifyDetailsScreenState extends State<VerifyDetailsScreen> {

  /// Controllers used to manage the text input of each field
  /// These will later be filled automatically by OCR results
  final _plateController = TextEditingController(text: "A B C 5432");
  final _modelController = TextEditingController(text: "cx5");
  final _colorController = TextEditingController(text: "White");
  final _makeController = TextEditingController(text: "Mazda");
  final _yearController = TextEditingController(text: "2024");
  final _chassisController = TextEditingController(text: "ASJJWNBC54327483");

  /// Global key used to validate the form inputs
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // Dispose controllers to free memory when the screen is removed
    _plateController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _makeController.dispose();
    _yearController.dispose();
    _chassisController.dispose();
    super.dispose();
  }

  /// Returns the decoration style used for all text fields
  /// This keeps the UI consistent across all inputs
  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black87),

      // Fill the background of the input
      filled: true,
      fillColor: Colors.white,

      // Padding inside the field
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),

      // Border when the field is not focused
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF9BB3D2), width: 1.2),
      ),

      // Border when the field is focused
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0D4B8C), width: 1.6),
      ),
    );
  }

  /// Called when the user presses "+ Add Vehicle"
  /// Currently only validates the form and shows a success dialog
  /// Backend logic will be added later
  void _onAddVehicle() {

    // Stop if the form has invalid fields
    if (!_formKey.currentState!.validate()) return;

    // Show success dialog
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),

            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                /// Success icon
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE7F6EC),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Color(0xFF2E7D32),
                    size: 34,
                  ),
                ),

                const SizedBox(height: 14),

                /// Success message
                const Text(
                  "Your vehicle has been successfully added to\n"
                  "your account",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 14),

                /// OK button to close the dialog
                SizedBox(
                  width: 140,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D4B8C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),

                    child: const Text(
                      "Ok",
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      /// Page background color
      backgroundColor: const Color(0xFFF6F7FB),

      /// Top app bar
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,

        title: const Text(
          "Verify Details",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),

        iconTheme: const IconThemeData(color: Colors.black),
      ),

      body: SafeArea(

        /// Page padding
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),

          /// Form widget to validate inputs
          child: Form(
            key: _formKey,

            child: Column(
              children: [

                /// Instruction text
                const Text(
                  "Verify or edit details if needed.",
                  style: TextStyle(
                    color: Color(0xFF8A97A6),
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 12),

                /// Scrollable area for the fields
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [

                        const SizedBox(height: 6),

                        /// Plate Number
                        TextFormField(
                          controller: _plateController,
                          decoration: _fieldDecoration("Plate Number"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? "Required"
                                  : null,
                        ),

                        const SizedBox(height: 12),

                        /// Vehicle Model
                        TextFormField(
                          controller: _modelController,
                          decoration: _fieldDecoration("Model"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? "Required"
                                  : null,
                        ),

                        const SizedBox(height: 12),

                        /// Vehicle Color
                        TextFormField(
                          controller: _colorController,
                          decoration: _fieldDecoration("Color"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? "Required"
                                  : null,
                        ),

                        const SizedBox(height: 12),

                        /// Vehicle Make
                        TextFormField(
                          controller: _makeController,
                          decoration: _fieldDecoration("Make"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? "Required"
                                  : null,
                        ),

                        const SizedBox(height: 12),

                        /// Vehicle Year
                        TextFormField(
                          controller: _yearController,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration("Year"),

                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return "Required";
                            }

                            final year = int.tryParse(v.trim());

                            if (year == null) {
                              return "Invalid year";
                            }

                            if (year < 1900 || year > 2100) {
                              return "Year out of range";
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 12),

                        /// Chassis Number
                        TextFormField(
                          controller: _chassisController,
                          decoration: _fieldDecoration("chasis Number"),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? "Required"
                                  : null,
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                /// Add Vehicle button
                SizedBox(
                  width: double.infinity,
                  height: 52,

                  child: ElevatedButton(
                    onPressed: _onAddVehicle,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D4B8C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    child: const Text(
                      "+ Add Vehicle",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
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