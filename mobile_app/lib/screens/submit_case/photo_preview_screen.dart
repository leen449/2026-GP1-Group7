import 'dart:io';
import 'package:flutter/material.dart';

class PhotoPreviewScreen extends StatelessWidget {
  final File? imageFile;
  final String? imageUrl;

  const PhotoPreviewScreen({super.key, this.imageFile, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: imageUrl != null
              ? Image.network(imageUrl!)
              : Image.file(imageFile!),
        ),
      ),
    );
  }
}
