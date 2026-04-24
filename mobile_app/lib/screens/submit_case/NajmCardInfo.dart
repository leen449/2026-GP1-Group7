import 'package:flutter/material.dart';

class NajmInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const NajmInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final iconBox = width < 360 ? 34.0 : 38.0;
    final iconSize = width < 360 ? 18.0 : 20.0;
    final labelSize = width < 360 ? 11.5 : 12.5;
    final valueSize = width < 360 ? 13.5 : 14.5;

    final displayValue = value.trim().isEmpty ? 'Not extracted' : value.trim();
    final isMissing = displayValue == 'Not extracted';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: width < 360 ? 12 : 14,
        vertical: width < 360 ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMissing ? Colors.red.shade100 : Colors.grey.shade300,
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: isMissing ? Colors.red.shade50 : const Color(0xFFEAF1F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: isMissing ? Colors.redAccent : const Color(0xFF0B4A7D),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: labelSize,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: valueSize,
                    color: isMissing ? Colors.redAccent : Colors.black87,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
