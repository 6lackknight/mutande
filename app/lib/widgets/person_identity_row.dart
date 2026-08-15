import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'contact_avatar.dart';

/// Avatar + name + handle stack used on Network People.
///
/// Wax-seal marks, name/handle contrast, hover ink shift. Collab home
/// list density: 36px mark, 10px row pad, stadium “you” pill.
class PersonIdentityRow extends StatefulWidget {
  const PersonIdentityRow({
    super.key,
    required this.title,
    required this.handle,
    this.subtitle,
    this.avatarUrl,
    this.leading,
    this.badge,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.isSelf = false,
  });

  static const avatarSize = 36.0;

  final String title;
  final String handle;

  /// Defaults to the lowercase handle. Broadcast/external can override.
  final String? subtitle;
  final String? avatarUrl;

  /// Replaces the avatar (broadcast / link marks).
  final Widget? leading;

  /// Stadium chip, e.g. “you”.
  final Widget? badge;
  final List<Widget>? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final bool isSelf;

  /// Postage-stamp chip — amber is the “you / pending” token.
  static Widget statusPill({
    required String label,
    Color foreground = MutandeColors.amber,
    Color background = MutandeColors.amberSoft,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          height: 1,
          color: foreground,
        ),
      ),
    );
  }

  @override
  State<PersonIdentityRow> createState() => _PersonIdentityRowState();
}

class _PersonIdentityRowState extends State<PersonIdentityRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduce ? Duration.zero : const Duration(milliseconds: 140);
    final address = widget.subtitle ?? formatMailAddress(widget.handle);
    final mark = widget.leading ??
        PersonAvatar(
          size: PersonIdentityRow.avatarSize,
          url: widget.avatarUrl,
          initials: personInitials(widget.title),
          seed: widget.handle,
          isSelf: widget.isSelf,
        );

    final actions = widget.trailing == null || widget.trailing!.isEmpty
        ? null
        : AnimatedOpacity(
            duration: duration,
            curve: Curves.easeOutCubic,
            opacity: _hover ? 1 : 0.5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.trailing!,
            ),
          );

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 4, 10),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.15,
                          color: MutandeColors.stone800,
                        ),
                      ),
                    ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: 8),
                      widget.badge!,
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: MutandeColors.stone500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          ?actions,
        ],
      ),
    );

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _hover ? MutandeColors.stone100 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Material(
              color: Colors.transparent,
              child: widget.onTap == null
                  ? row
                  : InkWell(
                      onTap: widget.onTap,
                      borderRadius: BorderRadius.circular(8),
                      splashColor:
                          MutandeColors.stone200.withValues(alpha: 0.55),
                      highlightColor:
                          MutandeColors.stone200.withValues(alpha: 0.3),
                      child: row,
                    ),
            ),
          ),
        ),
        if (widget.showDivider)
          const Divider(
            height: 1,
            indent: 54,
            color: MutandeColors.stone200,
          ),
      ],
    );
  }
}
