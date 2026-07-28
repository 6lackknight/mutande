import 'package:flutter/material.dart';

import '../services/host_link_store.dart';
import 'ai_host_icon.dart';
import 'host_link_status.dart';

/// Shared host catalog for Settings connect + Agents add flows.
class AiHostCatalog {
  static const hosts = <(String slug, String label)>[
    ('cursor', 'Cursor'),
    ('claude', 'Claude (Anthropic)'),
    ('chatgpt', 'ChatGPT'),
  ];
}

/// Pick one AI host to connect / link MCP config.
class ConnectHostPicker extends StatelessWidget {
  const ConnectHostPicker({
    super.key,
    required this.title,
    required this.subtitle,
    this.hosts = AiHostCatalog.hosts,
    this.hostLinks = const {},
  });

  final String title;
  final String subtitle;
  final List<(String, String)> hosts;
  final Map<String, HostLinkRecord> hostLinks;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFAFAF9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.link, size: 18, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF292524),
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF78716C),
                    ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < hosts.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFE7E5E4)),
                InkWell(
                  onTap: () => Navigator.pop(context, hosts[i].$1),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        AiHostIcon(hosts[i].$1, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            hosts[i].$2,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF292524),
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        HostLinkStatusBadge(
                          link: hostLinks[hosts[i].$1],
                          style: HostLinkStatusStyle.settings,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
