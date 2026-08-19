import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'contact_avatar.dart';
import 'person_identity_row.dart';

/// Org member chip on the team roster: person mark, address, known hosts.
class OnboardingRosterChip extends StatelessWidget {
  const OnboardingRosterChip({
    super.key,
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.isSelf = false,
    this.hostSlugs = const [],
    this.leading,
    this.onTap,
    this.semanticLabel,
  });

  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final bool isSelf;
  final List<String> hostSlugs;

  /// Replaces the person mark (host destinations on the handshake picker).
  final Widget? leading;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final title = personDisplayTitle(displayName: displayName, handle: handle);
    final address = formatMailAddress(handle);
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              PersonAvatar(
                size: 40,
                url: avatarUrl,
                initials: personInitials(title),
                seed: handle,
                isSelf: isSelf,
              ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MutandeColors.stone800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      PersonIdentityRow.statusPill(label: 'you'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: MutandeColors.stone500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (hostSlugs.isNotEmpty) ...[
            const SizedBox(width: 12),
            OnboardingHostAvatarStack(hostSlugs),
          ],
        ],
      ),
    );

    final chip = Container(
      constraints: const BoxConstraints(maxWidth: 300, minHeight: 56),
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: child,
    );

    if (onTap == null) return chip;

    return Semantics(
      button: true,
      label: semanticLabel ?? title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: chip,
        ),
      ),
    );
  }
}

/// Circular host mark sized to the roster person avatar.
class OnboardingHostLeading extends StatelessWidget {
  const OnboardingHostLeading(this.slug, {super.key, this.size = 40});

  final String slug;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        shape: BoxShape.circle,
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: AiHostIcon(slug, size: size * 0.6, showPlate: false),
    );
  }
}

/// Overlapping host marks for agents we already know on this handle.
class OnboardingHostAvatarStack extends StatelessWidget {
  const OnboardingHostAvatarStack(this.slugs, {super.key});

  final List<String> slugs;

  static const _size = 24.0;
  static const _overlap = 9.0;

  @override
  Widget build(BuildContext context) {
    final shown = slugs.take(3).toList();
    final extra = slugs.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final width = _size + (count - 1) * (_size - _overlap);
    final names = shown.map(AiHostIcon.displayName).join(', ');
    return Tooltip(
      message: extra > 0 ? '$names +$extra' : names,
      child: SizedBox(
        width: width,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: i * (_size - _overlap),
                child: _HostStackDot(shown[i]),
              ),
            if (extra > 0)
              Positioned(
                left: shown.length * (_size - _overlap),
                child: _HostStackMore('+$extra'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HostStackDot extends StatelessWidget {
  const _HostStackDot(this.slug);

  final String slug;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnboardingHostAvatarStack._size,
      height: OnboardingHostAvatarStack._size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        shape: BoxShape.circle,
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: AiHostIcon(slug, size: 15, showPlate: false),
    );
  }
}

class _HostStackMore extends StatelessWidget {
  const _HostStackMore(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: OnboardingHostAvatarStack._size,
      height: OnboardingHostAvatarStack._size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MutandeColors.stone800,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MutandeColors.stone50,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
