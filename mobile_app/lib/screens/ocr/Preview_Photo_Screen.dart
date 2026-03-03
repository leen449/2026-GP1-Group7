import 'dart:io'; // Used to display image from local file path
import 'package:flutter/material.dart';

/// This page displays the captured image
/// and allows the user to either retake the photo
/// or confirm and use the image.
class PhotoPreviewScreen extends StatelessWidget {
  final String imagePath; // The local path of the captured image

  const PhotoPreviewScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Light background 
      backgroundColor: const Color(0xFFF6F7FB),

      // Transparent AppBar with centered title
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Preview Photo",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              const SizedBox(height: 16),

              // Main card container
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      /// Image preview section
                      /// Displays the captured image from file path
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            color: const Color(0xFFF1F3F7),
                            child: Image.file(
                              File(imagePath), // Load image from file
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      /// Instruction text
                      /// Reminds user to check image clarity
                      const Text(
                        "Ensure all text is sharp and readable\nbefore proceeding.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8A97A6),
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// Action buttons (Retake / Use Photo)
                      Row(
                        children: [
                          /// Retake button
                          /// Returns null to indicate user wants to retake
                          Expanded(
                            child: _OutlinedActionButton(
                              label: "Retake",
                              icon: Icons.refresh,
                              onTap: () {
                                Navigator.pop(context, null);
                              },
                            ),
                          ),

                          const SizedBox(width: 12),

                          /// Use Photo button
                          /// Returns imagePath to confirm selection
                          Expanded(
                            child: _PrimaryActionButton(
                              label: "Use photo",
                              icon: Icons.check_box_outlined,
                              onTap: () {
                                Navigator.pop(context, imagePath);
                              },),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary blue button used for confirming the image
class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D4B8C),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// Secondary outlined button used for retaking the photo
class _OutlinedActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlinedActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: const Color(0xFF0D4B8C)),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0D4B8C),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD3DCE7)),
          backgroundColor: const Color(0xFFF2F4F8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}