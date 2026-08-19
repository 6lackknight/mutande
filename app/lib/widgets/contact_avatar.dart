import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Wax-seal plate for a person mark — stone/bronze only (amber is “you”).
typedef PersonMarkPlate = ({Color fill, Color ink});

PersonMarkPlate personMarkPlate(String seed, {bool isSelf = false}) {
  if (isSelf) {
    return (fill: MutandeColors.stone800, ink: MutandeColors.stone50);
  }
  const plates = <PersonMarkPlate>[
    (fill: MutandeColors.bronzeSoft, ink: MutandeColors.bronze),
    (fill: Color(0xFFE8E4DC), ink: MutandeColors.stone800),
    (fill: MutandeColors.stone200, ink: MutandeColors.stone800),
    (fill: Color(0xFFD6CFC6), ink: MutandeColors.bronze),
  ];
  var n = 0;
  for (final u in seed.trim().toLowerCase().codeUnits) {
    n = 0x1fffffff & (n * 31 + u);
  }
  return plates[n % plates.length];
}

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
        // Auth0/Google IdP photos often 403 the default Dart user-agent.
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
          'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
        },
        errorBuilder: (_, _, _) => fallbackChild,
      );
    }
    return fallbackChild;
  }
}

/// Circular person mark: hub `avatar_url` when present, else sealed initials.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.size,
    required this.initials,
    this.url,
    this.seed,
    this.isSelf = false,
  });

  final double size;
  final String initials;
  final String? url;
  final String? seed;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final plate = personMarkPlate(seed ?? initials, isSelf: isSelf);
    final photo = url?.trim();
    final fallback = ColoredBox(
      color: plate.fill,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: plate.ink,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: plate.fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelf
              ? MutandeColors.stone800
              : plate.ink.withValues(alpha: 0.18),
        ),
      ),
      child: (photo != null && photo.isNotEmpty)
          ? ContactAvatar(url: photo, size: size, fallback: fallback)
          : fallback,
    );
  }
}
