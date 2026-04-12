// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

enum PopupType {
  success,
  warning,
  error,
  confirm,
}

Future<void> showSystemPopup({
  required BuildContext context,
  required PopupType type,
  required String title,
  required String message,
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  String confirmText = 'Oke',
  String cancelText = 'Kembali',
  bool barrierDismissible = false,
}) {
  return showDialog(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => _SystemPopupDialog(
      type: type,
      title: title,
      message: message,
      onConfirm: onConfirm,
      onCancel: onCancel,
      confirmText: confirmText,
      cancelText: cancelText,
    ),
  );
}

class _SystemPopupDialog extends StatelessWidget {
  final PopupType type;
  final String title;
  final String message;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final String confirmText;
  final String cancelText;

  const _SystemPopupDialog({
    required this.type,
    required this.title,
    required this.message,
    this.onConfirm,
    this.onCancel,
    required this.confirmText,
    required this.cancelText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(theme),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                  fontSize: 24,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 18,
                  height: 1.6,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 28),
              _buildButtons(context, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    late final IconData icon;
    late final Color color;

    switch (type) {
      case PopupType.success:
        icon = Icons.check_circle_rounded;
        color = theme.colorScheme.secondary;
        break;
      case PopupType.warning:
        icon = Icons.warning_rounded;
        color = Colors.orange;
        break;
      case PopupType.error:
        icon = Icons.error_rounded;
        color = Colors.redAccent;
        break;
      case PopupType.confirm:
        icon = Icons.help_rounded;
        color = Colors.orange;
        break;
    }

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
      ),
      child: Icon(icon, size: 56, color: color),
    );
  }

  Widget _buildButtons(BuildContext context, ThemeData theme) {
    if (type == PopupType.confirm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PopupButton(
            text: confirmText,
            backgroundColor: theme.colorScheme.primary,
            textColor: Colors.white,
            onTap: () {
              Navigator.of(context).pop();
              onConfirm?.call();
            },
          ),
          const SizedBox(height: 12),
          _PopupButton(
            text: cancelText,
            backgroundColor: Colors.grey.shade300,
            textColor: Colors.black87,
            onTap: () {
              Navigator.of(context).pop();
              onCancel?.call();
            },
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: _PopupButton(
        text: confirmText,
        backgroundColor: theme.colorScheme.primary,
        textColor: Colors.white,
        onTap: () {
          Navigator.of(context).pop();
          onConfirm?.call();
        },
      ),
    );
  }
}

class _PopupButton extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onTap;

  const _PopupButton({
    // ignore: unused_element_parameter
    super.key,
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 1.0,
                ),
          ),
        ),
      ),
    );
  }
}