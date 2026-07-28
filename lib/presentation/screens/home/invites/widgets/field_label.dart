import 'package:flutter/material.dart';

class FieldLabel extends StatelessWidget {
  final String label;
  final Color textColor;

  const FieldLabel({super.key, required this.label, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: textColor,
      ),
    );
  }
}
