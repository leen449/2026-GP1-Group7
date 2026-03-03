import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'guided_damage_capture_screen.dart';
import 'photo_preview_screen.dart';

class VehicleItem {
  final String name;
  final String plate;
  const VehicleItem(this.name, this.plate);
}

class SubmitCaseScreen extends StatefulWidget {
  const SubmitCaseScreen({super.key});
  @override
  State<SubmitCaseScreen> createState() => _SubmitCaseScreenState();
}

class _SubmitCaseScreenState extends State<SubmitCaseScreen> {
  List<File> capturedPhotos = [];
  final List<VehicleItem> vehicles = const [
    VehicleItem('Toyota Camry', 'A S F R 3456'),
    VehicleItem('Ford Explorer', 'A D W R 3456'),
  ];

  VehicleItem? selectedVehicle;
  String? najmFileName;
  String? najmFilePath;
  DateTime? najmPickedAt;
  int? najmFileBytes;

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> pickNajmPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null) return;

    final picked = result.files.single;

    setState(() {
      najmFileName = picked.name;
      najmFilePath = picked.path;
      najmPickedAt = DateTime.now();
      najmFileBytes = picked.size;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Submit A Case',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Vehicle selector ──────────────────────
                          const Text('Select vehicle'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<VehicleItem>(
                            value: selectedVehicle,
                            isExpanded: true,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2F6FED),
                                  width: 1.5,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                  width: 1.2,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                            hint: const Text('Select'),
                            icon: const Icon(Icons.keyboard_arrow_down),
                            items: vehicles.map((v) {
                              return DropdownMenuItem<VehicleItem>(
                                value: v,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        v.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      v.plate,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => selectedVehicle = value),
                          ),

                          // ── Najm report upload ────────────────────
                          const SizedBox(height: 40),
                          const Text('Upload najm report'),
                          const SizedBox(height: 8),
                          if (najmFileName == null) ...[
                            InkWell(
                              onTap: pickNajmPdf,
                              borderRadius: BorderRadius.circular(12),
                              child: DottedBorder(
                                color: const Color(0xFF2F6FED),
                                dashPattern: const [6, 4],
                                strokeWidth: 1.5,
                                borderType: BorderType.RRect,
                                radius: const Radius.circular(12),
                                child: const SizedBox(
                                  height: 130,
                                  width: double.infinity,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.upload_file,
                                        size: 36,
                                        color: Colors.black54,
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'upload file',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'supported format: PDF',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          najmFileName!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'just now',
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      najmFileBytes == null
                                          ? ''
                                          : formatBytes(najmFileBytes!),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        najmFileName = null;
                                        najmFilePath = null;
                                        najmPickedAt = null;
                                        najmFileBytes = null;
                                      });
                                    },
                                    child: const Icon(Icons.close, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── Take Damage Photos ────────────────────
                          const SizedBox(height: 70),
                          const Text('Take Damage Photos'),
                          const Text(
                            '10 images maximum',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 12),

                          // Button
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final result = await Navigator.push<List<File>>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const GuidedDamageCaptureScreen(),
                                  ),
                                );

                                if (result == null || result.isEmpty) return;

                                setState(() {
                                  capturedPhotos = result;
                                });
                              },
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Take Photos',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0B4A7D),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 6,
                              ),
                            ),
                          ),

                          // ✅ Only renders when there are photos — no empty gap
                          if (capturedPhotos.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 80,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: capturedPhotos.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  return Stack(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PhotoPreviewScreen(
                                                    imageFile:
                                                        capturedPhotos[index],
                                                  ),
                                            ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.file(
                                            capturedPhotos[index],
                                            width: 70,
                                            height: 70,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              capturedPhotos.removeAt(index);
                                            });
                                          },
                                          child: Container(
                                            width: 18,
                                            height: 18,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],

                          const SizedBox(height: 40),
                        ],
                      ),
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
