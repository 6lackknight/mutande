// Inspector sidebar — kind/status/dates/files, copyable thread id, people chips.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import 'ai_host_icon.dart';

class ThreadInspectorSidebar extends StatelessWidget {
  const ThreadInspectorSidebar({
    super.key,
    required this.detail,
    this.myHandle,
  });

  final ThreadDetailResult detail;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final kind = _kindLabel(detail.kind);
    var files = 0;
    var upvotes = 0;
    DateTime? first;
    DateTime? last;
    for (final m in detail.messages) {
      files += m.resources.length;
      upvotes += m.upvotes?.count ?? 0;
      final t = DateTime.tryParse(m.createdAt);
      if (t == null) continue;
      if (first == null || t.isBefore(first)) first = t;
      if (last == null || t.isAfter(last)) last = t;
    }
    final participants = _participants(detail);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Text(
          'THREAD',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: MutandeColors.stone400,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 12),
        if (kind != null) _Fact(label: 'Kind', value: kind),
        _Fact(
          label: 'Status',
          value: detail.status == 'closed' ? 'Closed' : 'Open',
        ),
        if (first != null)
          _Fact(
            label: 'Started',
            value: formatRelativeTime(first.toIso8601String()),
          ),
        if (last != null)
          _Fact(
            label: 'Latest',
            value: formatRelativeTime(last.toIso8601String()),
          ),
        _Fact(label: 'Messages', value: '${detail.messages.length}'),
        if (files > 0) _Fact(label: 'Files', value: '$files'),
        if (upvotes > 0) _Fact(label: 'Upvotes', value: '$upvotes'),
        const SizedBox(height: 8),
        _CopyId(id: detail.id),
        const SizedBox(height: 18),
        Text(
          'PEOPLE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: MutandeColors.stone400,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in participants)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: _PersonChip(
                      handle: p,
                      label: formatMailAddress(p, myHandle: myHandle),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MutandeColors.stone400,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MutandeColors.stone800,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyId extends StatelessWidget {
  const _CopyId({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final short = id.length <= 12 ? id : '${id.substring(0, 8)}…';
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: id));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Thread id copied')));
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                short,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MutandeColors.stone500,
                  fontSize: 11,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
            const Icon(Icons.copy, size: 12, color: MutandeColors.stone400),
          ],
        ),
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.handle, required this.label});

  final String handle;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: MutandeColors.stone100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Mark(handle: handle, label: label, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MutandeColors.stone800,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.handle, required this.label, required this.size});

  final String handle;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final host = _hostSlug(handle);
    if (host != null) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: AiHostIcon(host, size: size, showPlate: false),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MutandeColors.stone100,
        shape: BoxShape.circle,
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Text(
        _initials(label),
        style: TextStyle(
          color: MutandeColors.stone500,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

String? _kindLabel(String kind) {
  switch (kind.trim().toLowerCase()) {
    case 'broadcast':
      return 'Broadcast';
    case 'direct':
      return null;
    case '':
      return null;
    default:
      return kind[0].toUpperCase() + kind.substring(1);
  }
}

Set<String> _participants(ThreadDetailResult d) {
  final out = <String>{};
  if (d.from.isNotEmpty) out.add(d.from);
  for (final m in d.messages) {
    if (m.fromHandle.isNotEmpty) out.add(m.fromHandle);
  }
  if (d.audience.isNotEmpty &&
      d.audience != d.from &&
      d.audience.trim() != '@all') {
    out.add(d.audience);
  }
  return out;
}

String? _hostSlug(String handle) {
  final lower = handle.toLowerCase();
  final slash = lower.lastIndexOf('/');
  final slug = slash >= 0
      ? lower.substring(slash + 1)
      : lower.replaceFirst('@', '');
  if (AiHostIcon.assetFor(slug) != null) return slug;
  return null;
}

String _initials(String label) {
  final bare = label.split('/').first;
  final local = bare.contains('@') ? bare.split('@').first : bare;
  final cleaned = local.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (cleaned.isEmpty) return '?';
  if (cleaned.length == 1) return cleaned.toUpperCase();
  return cleaned.substring(0, 2).toUpperCase();
}
