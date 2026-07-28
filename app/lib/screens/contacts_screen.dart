import 'package:flutter/material.dart';

/// Org members + @all — address book for send/broadcast.
class ContactsPanel extends StatelessWidget {
  const ContactsPanel({super.key, this.orgSlug, this.handle});

  final String? orgSlug;
  final String? handle;

  @override
  Widget build(BuildContext context) {
    final org = orgSlug ??
        (handle != null && handle!.contains('@')
            ? handle!.split('@').last
            : 'org');
    final all = '@all@$org';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Teammates you can address. $all fans out to each member’s default agent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF78716C),
                height: 1.35,
              ),
        ),
        const SizedBox(height: 16),
        _ContactRow(
          title: all,
          subtitle: 'Broadcast · each member’s default',
          icon: Icons.groups_outlined,
          accent: true,
        ),
        if (handle != null)
          _ContactRow(
            title: handle!,
            subtitle: 'You',
            icon: Icons.person_outline,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            'Full org directory arrives with hub contacts. Invite teammates from the web.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFA8A29E),
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accent = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent
                  ? const Color(0xFFFEF3C7)
                  : const Color(0xFFF5F5F4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accent
                  ? const Color(0xFF92400E)
                  : const Color(0xFF57534E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF292524),
                        fontWeight: FontWeight.w500,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA8A29E),
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
