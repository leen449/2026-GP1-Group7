import 'package:flutter/material.dart';
import 'package:dotted_border/dotted_border.dart';

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
  final List<VehicleItem> vehicles = const [
    VehicleItem('Toyota Camry', 'A S F R 3456'),
    VehicleItem('Ford Explorer', 'A D W R 3456'),
  ];

  VehicleItem? selectedVehicle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
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
                const SizedBox(height: 20),

                // Card container
                Container(
                  width: double.infinity, // ✅ important for layout
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          0.12,
                        ), // ✅ softer shadow
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select vehicle'),
                      const SizedBox(height: 8),

                      DropdownButtonFormField<VehicleItem>(
                        value: selectedVehicle,
                        isExpanded: true, // ✅ prevents weird shrinking
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
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

                      const SizedBox(height: 20),
                      const Text('Upload najm report'),
                      const SizedBox(height: 8),

                      DottedBorder(
                        color: const Color(0xFF2F6FED),
                        dashPattern: const [6, 4],
                        strokeWidth: 1.5,
                        borderType: BorderType.RRect,
                        radius: const Radius.circular(12),
                        child: SizedBox(
                          height: 110,
                          width: double.infinity,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.upload_file,
                                size: 36,
                                color: Colors.black54,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'upload file',
                                style: TextStyle(fontWeight: FontWeight.w600),
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

                      const SizedBox(height: 20),
                      const Text('Take Damage Photos'),
                      const Text(
                        '10 images maximum',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),

                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () {},
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
                    ],
                  ),
                ),

                const SizedBox(
                  height: 40,
                ), // ✅ extra space at bottom for scroll
              ],
            ),
          ),
        ),
      ),
    );
  }
}
