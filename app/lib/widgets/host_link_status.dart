import 'package:flutter/material.dart';

import '../services/host_link_store.dart';

/// Visual treatment for MCP link state (matches Settings → AI hosts).
enum HostLinkStatusStyle { settings, graph }

/// Resolve persisted link for a known AI host slug (`cursor`, `claude`, `chatgpt`).
HostLinkRecord? hostLinkForSlug(
  String slug,
  Map<String, HostLinkRecord> links,
) {
  final host = slug.trim().toLowerCase();
  if (host == 'cursor' || host == 'claude' || host == 'chatgpt') {
    return links[host];
  }
  return null;
}

class HostLinkStatusBadge extends StatelessWidget {
  const HostLinkStatusBadge({
    super.key,
    required this.link,
    this.style = HostLinkStatusStyle.graph,
  });

  final HostLinkRecord? link;
  final HostLinkStatusStyle style;

  @override
  Widget build(BuildContext context) {
    if (link == null) {
      if (style == HostLinkStatusStyle.settings) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F4),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Not linked',
            style: TextStyle(
              color: Color(0xFF78716C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      return _graphRow(
        dot: const Color(0xFFA8A29E),
        label: 'Not linked',
        labelColor: const Color(0xFF78716C),
      );
    }
    if (link!.ok) {
      if (style == HostLinkStatusStyle.settings) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'Linked',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      return _graphRow(
        dot: const Color(0xFF166534),
        label: 'Linked',
        labelColor: const Color(0xFF78716C),
        letterSpacing: 0.6,
      );
    }
    if (style == HostLinkStatusStyle.settings) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Failed',
          style: TextStyle(
            color: Color(0xFF991B1B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return _graphRow(
      dot: const Color(0xFF991B1B),
      label: 'Failed',
      labelColor: const Color(0xFF991B1B),
    );
  }

  Widget _graphRow({
    required Color dot,
    required String label,
    required Color labelColor,
    double letterSpacing = 0,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        SizedBox(width: style == HostLinkStatusStyle.graph ? 5 : 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: labelColor,
              letterSpacing: letterSpacing,
              fontSize: style == HostLinkStatusStyle.graph ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Inspector field: plain label + dot color.
  static (String label, Color dotColor) resolve(HostLinkRecord? link) {
    if (link == null) {
      return ('Not linked', const Color(0xFFA8A29E));
    }
    if (link.ok) {
      return ('Linked', const Color(0xFF16A34A));
    }
    return ('Failed', const Color(0xFF991B1B));
  }
}
