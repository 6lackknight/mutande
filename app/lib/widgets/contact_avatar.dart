import 'dart:convert';

import 'package:flutter/material.dart';

/// Profile photo (https or data URL) clipped to a circle.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.url,
    required this.size,
    this.fallback,
  });

  final String url;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _image(),
      ),
    );
  }

  Widget _image() {
    final fallbackChild = fallback ?? const SizedBox.shrink();
    if (url.startsWith('data:image/')) {
      final comma = url.indexOf(',');
      if (comma < 0) return fallbackChild;
      try {
        final bytes = base64Decode(url.substring(comma + 1));
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallbackChild,
        );
      } catch (_) {
        return fallbackChild;
      }
    }
    if (url.startsWith('https://') || url.startsWith('http://')) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallbackChild,
      );
    }
    return fallbackChild;
  }
}
