import 'package:flutter/material.dart';

class SettingsSliderRow extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final Widget child;

  static const TextStyle _labelStyle = TextStyle(fontSize: 11, color: Colors.grey);

  const SettingsSliderRow({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(leftLabel, style: _labelStyle),
        Expanded(child: child),
        Text(rightLabel, style: _labelStyle),
      ]);
}