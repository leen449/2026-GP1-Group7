import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'guided_damage_capture_screen.dart';
import 'photo_preview_screen.dart';
import 'CaseSubmittedScreen.dart';
import '../ocr/Ocr_Screen.dart';
import '../home/home_screen.dart';
import 'dart:ui';

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
  int _currentIndex = 1; // ✅ Set to 1 since this is the "accident" tab
  final List<VehicleItem> vehicles = const [
    VehicleItem('Toyota Camry', 'A S F R 3456'),
    VehicleItem('Ford Explorer', 'A D W R 3456'),
  ];

  VehicleItem? selectedVehicle;
  String? najmFileName;
  String? najmFilePath;
  DateTime? najmPickedAt;
  int? najmFileBytes;

  bool get canSubmit =>
      selectedVehicle != null &&
      najmFileName != null &&
      capturedPhotos.isNotEmpty;

  Future<void> _showConfirmDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Confirm National ID',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Please confirm that your National ID is correct. Once submitted, it cannot be edited.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.black87,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'cancel',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CaseSubmittedScreen()),
      );
    }
  }

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

  void _onNavTap(int index) {
    if (index == _currentIndex) return;

    if (index == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() => _currentIndex = index);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Tab ${index + 1} coming soon")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      // ✅ THIS is what was missing — bottomNavigationBar properly wired up
      bottomNavigationBar: _bottomNav(),
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

                // ── Grey card ─────────────────────────────────────────
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
                          // ── Vehicle selector ────────────────────────
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

                          // ── Najm report upload ───────────────────────
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

                          // ── Take Damage Photos ───────────────────────
                          const SizedBox(height: 40),
                          const Text('Take Damage Photos'),
                          const Text(
                            '10 images maximum',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 12),

                          if (capturedPhotos.isEmpty)
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final result =
                                      await Navigator.push<List<File>>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const GuidedDamageCaptureScreen(),
                                        ),
                                      );
                                  if (result == null || result.isEmpty) return;
                                  setState(() => capturedPhotos = result);
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

                          if (capturedPhotos.isNotEmpty)
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
                                            setState(
                                              () => capturedPhotos.removeAt(
                                                index,
                                              ),
                                            );
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

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),

                // ✅ Submit button — outside grey card
                if (canSubmit) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton(
                      onPressed: _showConfirmDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4A7D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 6,
                      ),
                      child: const Text(
                        'Submit Case',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ Now properly used via bottomNavigationBar: _bottomNav()
  Widget _bottomNav() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.35),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Colors.white.withOpacity(0.50),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(index: 0, label: 'home', icon: Icons.home_rounded),
                  _navItem(
                    index: 1,
                    label: 'accident',
                    icon: Icons.directions_car,
                  ),
                  _navItem(
                    index: 2,
                    label: 'history',
                    icon: Icons.description_outlined,
                  ),
                  _navItem(
                    index: 3,
                    label: 'claim',
                    icon: Icons.assignment_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool active = _currentIndex == index;
    const Color activeBlue = Color(0xFF2A5BD7);
    const Color inactiveGrey = Color(0xFF8A8A8A);

    return GestureDetector(
      onTap: () => _onNavTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 74,
        height: 50,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(index == _currentIndex),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                final shake = active
                    ? (value < 0.5 ? value * 2 * 6 : (1 - value) * 2 * 6)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(
                    shake * (value < 0.25 || value > 0.75 ? -1 : 1),
                    0,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: active ? activeBlue : inactiveGrey,
                  ),
                );
              },
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? activeBlue : inactiveGrey,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
