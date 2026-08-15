import 'package:flutter/material.dart';

/// Host mark for connectable AI apps (`cursor` · `claude` · `chatgpt`).
///
/// Renders each product PNG in its original colors on an optional plate.
class AiHostIcon extends StatelessWidget {
  const AiHostIcon(
    this.host, {
    super.key,
    this.size = 28,
    this.showPlate = true,
  });

  /// Host slug from daemon / MCP (`cursor`, `claude`, `chatgpt`, or agent slug).
  final String host;

  /// Outer size (plate diameter when [showPlate] is true).
  final double size;

  /// Soft rounded plate behind the mark (list rows / graph cards).
  final bool showPlate;

  static const _ink = Color(0xFF1C1917);
  static const _plate = Color(0xFFE7E5E4);
  static const _plateBorder = Color(0xFFD6D3D1);

  /// Product plates: Cursor is a black mark, Claude a white one.
  static Color _fillFor(String slug) {
    return switch (slug) {
      'cursor' => const Color(0xFF000000),
      'claude' => const Color(0xFFFFFFFF),
      _ => _plate,
    };
  }

  static Color _borderFor(String slug) {
    return switch (slug) {
      'cursor' => const Color(0xFF000000),
      'claude' => _plateBorder,
      _ => _plateBorder,
    };
  }

  static const _assets = {
    'cursor': 'assets/hosts/cursor.png',
    'claude': 'assets/hosts/claude.png',
    'chatgpt': 'assets/hosts/chatgpt.png',
  };

  static String? assetFor(String host) => _assets[host.toLowerCase()];

  static String displayName(String host) {
    switch (host.toLowerCase()) {
      case 'cursor':
        return 'Cursor';
      case 'claude':
        return 'Claude (Anthropic)';
      case 'chatgpt':
        return 'ChatGPT';
      default:
        return host;
    }
  }

  /// Outlined Material fallbacks — same subfamily when a mark is missing.
  static IconData fallbackIcon(String host) {
    switch (host.toLowerCase()) {
      case 'cursor':
        return Icons.code_outlined;
      case 'claude':
        return Icons.auto_awesome_outlined;
      case 'chatgpt':
        return Icons.chat_bubble_outline;
      default:
        return Icons.extension_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = host.toLowerCase();
    final asset = _assets[slug];
    // Fill most of the plate so marks read at a glance.
    final markSize = showPlate ? size * 0.72 : size;

    final mark = asset == null
        ? Icon(fallbackIcon(slug), size: markSize, color: _ink)
        : Image.asset(
            asset,
            width: markSize,
            height: markSize,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => Icon(
              fallbackIcon(slug),
              size: markSize,
              color: _ink,
            ),
          );

    if (!showPlate) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: mark),
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _fillFor(slug),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: _borderFor(slug), width: 1),
      ),
      child: mark,
    );
  }
}
