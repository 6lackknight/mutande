// Relay reading pane — OP quiet, latest heavier, markdown, awaiting meta,
// capsule composer, files as one stack. Stats rail stays beside this.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import '../util/clock_format.dart';
import 'ai_host_icon.dart';
import 'message_attachments.dart';
import 'thread_message_tree.dart';
import 'thread_status_badge.dart';

class ThreadRelayReading extends StatelessWidget {
  const ThreadRelayReading({
    super.key,
    required this.detail,
    required this.myHandle,
    required this.muted,
    required this.reply,
    required this.sending,
    required this.replyToHandle,
    required this.nested,
    required this.onSend,
    required this.onClearTarget,
    required this.onReply,
    required this.onUpvote,
    required this.upvotingId,
    required this.onRefresh,
    required this.onClose,
    required this.onDelete,
    this.onMuteToggle,
    this.leading = const [],
  });

  final ThreadDetailResult detail;
  final String? myHandle;
  final bool muted;
  final TextEditingController reply;
  final bool sending;
  final String? replyToHandle;
  final bool nested;
  final VoidCallback onSend;
  final VoidCallback onClearTarget;
  final ValueChanged<ThreadMessageView> onReply;
  final ValueChanged<ThreadMessageView> onUpvote;
  final String? upvotingId;
  final VoidCallback onRefresh;
  final VoidCallback? onClose;
  final VoidCallback onDelete;
  final VoidCallback? onMuteToggle;
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    return _VariantRelay(host: this);
  }
}

class _VariantRelay extends StatelessWidget {
  const _VariantRelay({required this.host});

  final ThreadRelayReading host;

  @override
  Widget build(BuildContext context) {
    final d = host.detail;
    final op = _op(d);
    final replies = _replies(d);
    final closed = d.status == 'closed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RelayHeader(host: host, op: op),
        for (final w in host.leading) ...[
          const SizedBox(height: 10),
          w,
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (op != null) ...[
                _MdBody(text: op.displayBody, recede: replies.isNotEmpty),
                if (op.resources.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PackageStack(resources: op.resources),
                ],
                const SizedBox(height: 8),
                _QuietActions(
                  message: op,
                  upvoting: host.upvotingId == op.id,
                  closed: closed,
                  onReply: () => host.onReply(op),
                  onUpvote: () => host.onUpvote(op),
                ),
              ],
              for (var i = 0; i < replies.length; i++) ...[
                const SizedBox(height: 18),
                _RelayReply(
                  message: replies[i],
                  myHandle: host.myHandle,
                  latest: i == replies.length - 1,
                  closed: closed,
                  upvoting: host.upvotingId == replies[i].id,
                  onReply: () => host.onReply(replies[i]),
                  onUpvote: () => host.onUpvote(replies[i]),
                ),
              ],
            ],
          ),
        ),
        _CapsuleComposer(
          controller: host.reply,
          sending: host.sending,
          closed: closed,
          replyToHandle: host.replyToHandle,
          nested: host.nested,
          onClearTarget: host.onClearTarget,
          onSend: host.onSend,
        ),
      ],
    );
  }
}

class _RelayHeader extends StatelessWidget {
  const _RelayHeader({required this.host, required this.op});

  final ThreadRelayReading host;
  final ThreadMessageView? op;

  @override
  Widget build(BuildContext context) {
    final d = host.detail;
    final from = formatMailAddress(
      op?.fromHandle ?? d.from,
      myHandle: host.myHandle,
    );
    final to = d.audience.isNotEmpty
        ? formatMailAddress(d.audience, myHandle: host.myHandle)
        : null;
    final showTo = to != null && to != from && d.audience != d.from;
    final status = ThreadStatusKindX.resolve(
      status: d.status,
      yourStatus: d.yourStatus,
    );
    final time = formatRelativeTime(op?.createdAt ?? d.messages.firstOrNull?.createdAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CircleMark(label: from, handle: op?.fromHandle ?? d.from, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: MutandeColors.stone800,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showTo)
                    Text(
                      'to $to',
                      style: const TextStyle(
                        color: MutandeColors.stone400,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (time.isNotEmpty)
                    Text(
                      time,
                      style: const TextStyle(
                        color: MutandeColors.stone400,
                        fontSize: 11,
                      ),
                    ),
                  if (status == ThreadStatusKind.needsYou)
                    const ThreadStatusBadge(
                      kind: ThreadStatusKind.needsYou,
                      compact: true,
                    )
                  else if (status == ThreadStatusKind.waiting && showTo)
                    Text(
                      'awaiting $to',
                      style: const TextStyle(
                        color: MutandeColors.bronze,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: host.onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          color: MutandeColors.stone400,
          visualDensity: VisualDensity.compact,
        ),
        PopupMenuButton<String>(
          tooltip: 'Thread actions',
          padding: EdgeInsets.zero,
          onSelected: (v) {
            if (v == 'mute') host.onMuteToggle?.call();
            if (v == 'close') host.onClose?.call();
            if (v == 'delete') host.onDelete();
          },
          itemBuilder: (context) => [
            if (host.onMuteToggle != null)
              PopupMenuItem(
                value: 'mute',
                child: Text(host.muted ? 'Unmute' : 'Mute'),
              ),
            if (host.onClose != null)
              const PopupMenuItem(value: 'close', child: Text('Close')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.more_horiz, size: 18, color: MutandeColors.stone400),
          ),
        ),
      ],
    );
  }
}

class _RelayReply extends StatelessWidget {
  const _RelayReply({
    required this.message,
    required this.myHandle,
    required this.latest,
    required this.closed,
    required this.upvoting,
    required this.onReply,
    required this.onUpvote,
  });

  final ThreadMessageView message;
  final String? myHandle;
  final bool latest;
  final bool closed;
  final bool upvoting;
  final VoidCallback onReply;
  final VoidCallback onUpvote;

  @override
  Widget build(BuildContext context) {
    final from = formatMailAddress(message.fromHandle, myHandle: myHandle);
    final time = formatRelativeTime(message.createdAt);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 2,
          height: 36,
          margin: const EdgeInsets.only(right: 10, top: 4),
          color: latest ? MutandeColors.stone600 : MutandeColors.stone200,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CircleMark(label: from, handle: message.fromHandle, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: latest
                            ? MutandeColors.stone800
                            : MutandeColors.stone500,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        color: MutandeColors.stone400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _MdBody(text: message.displayBody, recede: !latest),
              if (message.resources.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PackageStack(resources: message.resources),
              ],
              const SizedBox(height: 6),
              _QuietActions(
                message: message,
                upvoting: upvoting,
                closed: closed,
                onReply: onReply,
                onUpvote: onUpvote,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// B — Letter: mail letter, composer under the letter (no bottom canyon)
// ---------------------------------------------------------------------------


class _PackageStack extends StatelessWidget {
  const _PackageStack({required this.resources});

  final List<BundleResourceView> resources;

  @override
  Widget build(BuildContext context) {
    final n = resources.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                n == 1 ? '1 file' : '$n files',
                style: const TextStyle(
                  color: MutandeColors.stone400,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (var i = 0; i < resources.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _PackageLine(resource: resources[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackageLine extends StatelessWidget {
  const _PackageLine({required this.resource});

  final BundleResourceView resource;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: resource.hasPath
          ? () => openAttachmentPath(resource.path!)
          : null,
      onSecondaryTap: resource.hasPath
          ? () => revealAttachmentPath(resource.path!)
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            const Icon(
              LucideIcons.fileText,
              size: 14,
              color: MutandeColors.stone400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                resource.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MutandeColors.stone800,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (resource.sizeLabel != null)
              Text(
                resource.sizeLabel!,
                style: const TextStyle(
                  color: MutandeColors.stone400,
                  fontSize: 10.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MdBody extends StatelessWidget {
  const _MdBody({required this.text, this.recede = false});

  final String text;
  final bool recede;

  @override
  Widget build(BuildContext context) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return Text(
        '(no notes)',
        style: TextStyle(
          color: MutandeColors.stone400,
          fontSize: 13,
          fontStyle: FontStyle.italic,
          height: 1.45,
        ),
      );
    }
    final color = recede ? MutandeColors.stone600 : MutandeColors.stone800;
    final base = TextStyle(color: color, fontSize: 13.5, height: 1.45);
    final children = <Widget>[];
    var inCode = false;
    final code = StringBuffer();
    for (final line in raw.split('\n')) {
      final t = line.trimRight();
      if (t.trim().startsWith('```')) {
        if (inCode) {
          children.add(_code(code.toString()));
          code.clear();
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        code.writeln(t);
        continue;
      }
      if (t.startsWith('### ')) {
        children.add(_h(t.substring(4), 13, color));
      } else if (t.startsWith('## ')) {
        children.add(_h(t.substring(3), 14.5, color));
      } else if (t.startsWith('# ')) {
        children.add(_h(t.substring(2), 16, color));
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('·  ', style: base.copyWith(fontWeight: FontWeight.w700)),
                Expanded(child: Text.rich(_inline(t.substring(2), base))),
              ],
            ),
          ),
        );
      } else if (t.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(_inline(t, base)),
          ),
        );
      }
    }
    if (inCode && code.isNotEmpty) children.add(_code(code.toString()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _h(String t, double size, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }

  Widget _code(String t) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MutandeColors.stone100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t.trim(),
        style: const TextStyle(
          color: MutandeColors.stone600,
          fontSize: 12,
          height: 1.4,
          fontFamily: 'Menlo',
        ),
      ),
    );
  }

  TextSpan _inline(String t, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    var i = 0;
    for (final m in re.allMatches(t)) {
      if (m.start > i) spans.add(TextSpan(text: t.substring(i, m.start)));
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: base.copyWith(
              fontFamily: 'Menlo',
              fontSize: (base.fontSize ?? 13.5) - 0.5,
              backgroundColor: MutandeColors.stone100,
            ),
          ),
        );
      }
      i = m.end;
    }
    if (i < t.length) spans.add(TextSpan(text: t.substring(i)));
    return TextSpan(style: base, children: spans);
  }
}

class _CircleMark extends StatelessWidget {
  const _CircleMark({required this.label, required this.handle, this.size = 28});

  final String label;
  final String handle;
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

class _QuietActions extends StatelessWidget {
  const _QuietActions({
    required this.message,
    required this.upvoting,
    required this.closed,
    required this.onReply,
    required this.onUpvote,
  });

  final ThreadMessageView message;
  final bool upvoting;
  final bool closed;
  final VoidCallback onReply;
  final VoidCallback onUpvote;

  @override
  Widget build(BuildContext context) {
    final count = message.upvotes?.count ?? 0;
    final you = message.upvotes?.youUpvoted ?? false;
    return Row(
      children: [
        IconButton(
          tooltip: 'Upvote',
          onPressed: closed ? null : onUpvote,
          icon: Icon(
            LucideIcons.arrowBigUp,
            size: 16,
            color: you ? MutandeColors.bronze : MutandeColors.stone400,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        if (count > 0)
          Text(
            '$count',
            style: TextStyle(
              color: you ? MutandeColors.bronze : MutandeColors.stone400,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        IconButton(
          tooltip: 'Reply',
          onPressed: closed ? null : onReply,
          icon: const Icon(
            LucideIcons.cornerUpLeft,
            size: 15,
            color: MutandeColors.stone400,
          ),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        if (upvoting)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      ],
    );
  }
}

class _CapsuleComposer extends StatefulWidget {
  const _CapsuleComposer({
    required this.controller,
    required this.sending,
    required this.closed,
    required this.nested,
    required this.onClearTarget,
    required this.onSend,
    this.replyToHandle,
  });

  final TextEditingController controller;
  final bool sending;
  final bool closed;
  final bool nested;
  final String? replyToHandle;
  final VoidCallback onClearTarget;
  final VoidCallback onSend;

  @override
  State<_CapsuleComposer> createState() => _CapsuleComposerState();
}

class _CapsuleComposerState extends State<_CapsuleComposer> {
  bool _focused = false;
  late bool _hasText = widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  String get _hint {
    if (widget.closed) return 'Thread closed';
    if (widget.replyToHandle != null) {
      return 'Reply to ${widget.replyToHandle}…';
    }
    if (widget.nested) return 'Nested reply…';
    return 'Write a reply…';
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.closed && !widget.sending && _hasText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.replyToHandle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Replying to ${widget.replyToHandle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MutandeColors.stone500,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onClearTarget,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        Focus(
          onFocusChange: (v) => setState(() => _focused = v),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MutandeColors.stone100,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _focused ? MutandeColors.stone800 : MutandeColors.stone200,
                width: _focused ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      enabled: !widget.sending && !widget.closed,
                      minLines: 1,
                      maxLines: 6,
                      style: const TextStyle(
                        color: MutandeColors.stone800,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: _hint,
                        hintStyle: const TextStyle(
                          color: MutandeColors.stone400,
                          fontSize: 13.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: canSend
                        ? MutandeColors.stone800
                        : MutandeColors.stone200,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: canSend ? widget.onSend : null,
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          LucideIcons.arrowUp,
                          size: 15,
                          color: canSend
                              ? MutandeColors.stone50
                              : MutandeColors.stone400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

ThreadMessageView? _op(ThreadDetailResult d) {
  final nodes = flattenThreadMessages(d.messages);
  for (final n in nodes) {
    if (n.depth == 0 &&
        n.message.fromHandle.split('/').first.toLowerCase() ==
            d.from.split('/').first.toLowerCase()) {
      return n.message;
    }
  }
  for (final n in nodes) {
    if (n.depth == 0) return n.message;
  }
  return d.messages.isEmpty ? null : d.messages.first;
}

List<ThreadMessageView> _replies(ThreadDetailResult d) {
  final op = _op(d);
  return flattenThreadMessages(d.messages)
      .where((n) => op == null || n.message.id != op.id)
      .map((n) => n.message)
      .toList();
}

String? _hostSlug(String handle) {
  final lower = handle.toLowerCase();
  final slash = lower.lastIndexOf('/');
  final slug = slash >= 0 ? lower.substring(slash + 1) : lower.replaceFirst('@', '');
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
