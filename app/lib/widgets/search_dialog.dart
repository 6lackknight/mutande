import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';
import '../util/address_display.dart';
import 'ai_host_icon.dart';
import 'home_chrome_strip.dart';
import 'pane_quiet_state.dart';
import 'thinking_orb.dart';

enum SearchScope { all, threads, collab, contacts }

enum SearchHitKind { thread, collab, contact }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.hostSlug,
  });

  final SearchHitKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? hostSlug;
}

bool _needle(String q, Iterable<String?> fields) {
  return fields.any((f) => (f ?? '').toLowerCase().contains(q));
}

List<SearchHit> filterSearchHits({
  required String query,
  required SearchScope scope,
  required List<ThreadSummary> threads,
  required List<CollabSummary> collabs,
  required List<ContactView> contacts,
  String? myHandle,
}) {
  final q = query.trim().toLowerCase();
  final out = <SearchHit>[];

  if (scope == SearchScope.all || scope == SearchScope.threads) {
    for (final t in threads) {
      if (q.isNotEmpty &&
          !_needle(q, [
            t.from,
            t.audience,
            t.kind,
            t.status,
            t.agentBadge,
            t.lastFrom,
            t.lastSubject,
            t.lastPreview,
            t.collabName,
          ])) {
        continue;
      }
      final via = t.agentBadge;
      final host = (via != null &&
              via.isNotEmpty &&
              via != 'default' &&
              AiHostIcon.assetFor(via) != null)
          ? via.toLowerCase()
          : null;
      final subject = (t.lastSubject ?? '').trim();
      final title = subject.isNotEmpty
          ? subject
          : formatMailAddress(t.from, myHandle: myHandle);
      final meta = [
        formatMailAddress(t.from, myHandle: myHandle),
        if (t.collabName != null && t.collabName!.trim().isNotEmpty)
          t.collabName!.trim(),
        t.kind,
      ].join(' · ');
      out.add(
        SearchHit(
          kind: SearchHitKind.thread,
          id: t.id,
          title: title,
          subtitle: meta,
          hostSlug: host,
        ),
      );
    }
  }

  if (scope == SearchScope.all || scope == SearchScope.collab) {
    for (final c in collabs) {
      if (q.isNotEmpty && !_needle(q, [c.name, c.causeAddress])) continue;
      final cards = c.cardCount == 1 ? '1 card' : '${c.cardCount} cards';
      out.add(
        SearchHit(
          kind: SearchHitKind.collab,
          id: c.id,
          title: c.name,
          subtitle: '$cards · ${c.isE2e ? 'e2e' : 'app envelope'}',
        ),
      );
    }
  }

  if (scope == SearchScope.all || scope == SearchScope.contacts) {
    final seen = <String>{};
    for (final c in contacts) {
      final handle = c.handle.trim().toLowerCase();
      if (handle.isEmpty || !seen.add(handle)) continue;
      if (q.isNotEmpty && !_needle(q, [c.handle, c.displayName, c.kind])) {
        continue;
      }
      final name = (c.displayName ?? '').trim();
      out.add(
        SearchHit(
          kind: SearchHitKind.contact,
          id: handle,
          title: name.isNotEmpty ? name : handle,
          subtitle: name.isNotEmpty ? handle : (c.isBroadcast ? 'broadcast' : c.kind),
        ),
      );
    }
  }

  return out;
}

Future<SearchHit?> showSearchDialog({
  required BuildContext context,
  required DaemonClient daemon,
  String? myHandle,
  List<String> recentQueries = const [],
  ValueChanged<String>? onRememberQuery,
}) {
  final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<SearchHit>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Search',
    barrierColor: MutandeColors.stone100,
    transitionDuration: Duration(milliseconds: reduce ? 0 : 200),
    pageBuilder: (ctx, animation, secondary) {
      return SearchDialog(
        daemon: daemon,
        myHandle: myHandle,
        recentQueries: recentQueries,
        onRememberQuery: onRememberQuery,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) {
      if (reduce) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class SearchDialog extends StatefulWidget {
  const SearchDialog({
    super.key,
    required this.daemon,
    this.myHandle,
    this.recentQueries = const [],
    this.onRememberQuery,
  });

  final DaemonClient daemon;
  final String? myHandle;
  final List<String> recentQueries;
  final ValueChanged<String>? onRememberQuery;

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  SearchScope _scope = SearchScope.all;
  bool _loading = true;
  String? _error;
  List<ThreadSummary> _threads = const [];
  List<CollabSummary> _collabs = const [];
  List<ContactView> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTyped);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTyped);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    List<ThreadSummary> threads = const [];
    List<CollabSummary> collabs = const [];
    List<ContactView> contacts = const [];
    String? error;
    try {
      threads = await widget.daemon.listThreads();
    } catch (e) {
      error = friendlyDaemonError(e, what: 'Search');
    }
    try {
      collabs = (await widget.daemon.listCollabs()).collabs;
    } catch (e) {
      error ??= friendlyDaemonError(e, what: 'Search');
    }
    try {
      contacts = await widget.daemon.listContacts();
    } catch (e) {
      error ??= friendlyDaemonError(e, what: 'Search');
    }
    try {
      final extra = await widget.daemon.listExternalContacts();
      final seen = {for (final c in contacts) c.handle.trim().toLowerCase()};
      contacts = [
        ...contacts,
        ...extra.where((c) => seen.add(c.handle.trim().toLowerCase())),
      ];
    } catch (_) {
      // Older daemons omit external contacts.
    }
    if (!mounted) return;
    setState(() {
      _threads = threads;
      _collabs = collabs;
      _contacts = contacts;
      _error = (threads.isEmpty && collabs.isEmpty && contacts.isEmpty)
          ? error
          : null;
      _loading = false;
    });
  }

  List<SearchHit> get _hits {
    return filterSearchHits(
      query: _controller.text,
      scope: _scope,
      threads: _threads,
      collabs: _collabs,
      contacts: _contacts,
      myHandle: widget.myHandle,
    );
  }

  void _close() => Navigator.of(context).pop();

  void _pick(SearchHit hit) {
    final q = _controller.text.trim();
    if (q.isNotEmpty) widget.onRememberQuery?.call(q);
    Navigator.of(context).pop(hit);
  }

  void _pickRecent(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    widget.onRememberQuery?.call(q);
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: MutandeColors.stone100,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _CloseButton(onPressed: _close),
                        const SizedBox(width: 12),
                        Text(
                          'Search',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: MutandeColors.stone800,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const Spacer(),
                        const Text(
                          'esc',
                          style: TextStyle(
                            color: MutandeColors.stone400,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DialogSearchField(
                      controller: _controller,
                      focusNode: _focus,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _ScopeChip(
                          key: const Key('search-scope-all'),
                          icon: CupertinoIcons.square_stack,
                          label: 'All',
                          selected: _scope == SearchScope.all,
                          onTap: () =>
                              setState(() => _scope = SearchScope.all),
                        ),
                        _ScopeChip(
                          key: const Key('search-scope-threads'),
                          icon: CupertinoIcons.envelope,
                          label: 'Threads',
                          selected: _scope == SearchScope.threads,
                          onTap: () =>
                              setState(() => _scope = SearchScope.threads),
                        ),
                        _ScopeChip(
                          key: const Key('search-scope-collab'),
                          icon: CupertinoIcons.rectangle_split_3x1,
                          label: 'Collab',
                          selected: _scope == SearchScope.collab,
                          onTap: () =>
                              setState(() => _scope = SearchScope.collab),
                        ),
                        _ScopeChip(
                          key: const Key('search-scope-contacts'),
                          icon: CupertinoIcons.person,
                          label: 'Contacts',
                          selected: _scope == SearchScope.contacts,
                          onTap: () =>
                              setState(() => _scope = SearchScope.contacts),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final q = _controller.text.trim();
    if (_loading) {
      return const Center(
        child: MutandeOrb.standard(semanticLabel: 'Searching…'),
      );
    }
    if (_error != null) {
      return PaneQuietState(
        title: "Couldn't search",
        body: _error,
        onRetry: _load,
        icon: Icons.cloud_off_outlined,
      );
    }
    if (q.isEmpty && _scope == SearchScope.all) {
      return _EmptySearch(
        recent: widget.recentQueries,
        onPick: _pickRecent,
      );
    }
    final hits = _hits;
    if (hits.isEmpty) {
      final where = switch (_scope) {
        SearchScope.threads => 'threads',
        SearchScope.collab => 'collabs',
        SearchScope.contacts => 'contacts',
        SearchScope.all => 'collabs, threads, or contacts',
      };
      return Center(
        child: Text(
          q.isEmpty ? 'Nothing in $where yet' : 'No $where match “$q”',
          style: const TextStyle(color: MutandeColors.stone500),
        ),
      );
    }
    return _HitList(
      hits: hits,
      grouped: _scope == SearchScope.all,
      onPick: _pick,
    );
  }
}

class _DialogSearchField extends StatelessWidget {
  const _DialogSearchField({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: MutandeColors.stone50,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: focused ? MutandeColors.stone800 : MutandeColors.stone200,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                CupertinoIcons.search,
                size: 16,
                color: focused ? MutandeColors.stone800 : MutandeColors.stone400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  cursorColor: MutandeColors.stone800,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: MutandeColors.stone800,
                        fontSize: 15,
                      ),
                  decoration: const InputDecoration(
                    hintText: 'Search collabs, threads, contacts',
                    hintStyle: TextStyle(
                      color: MutandeColors.stone400,
                      fontSize: 15,
                    ),
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.singleLineFormatter,
                  ],
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: controller.clear,
                  icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 16),
                  color: MutandeColors.stone400,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? MutandeColors.stone50 : MutandeColors.stone600;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: selected ? MutandeColors.stone800 : MutandeColors.stone100,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? MutandeColors.stone800 : MutandeColors.stone200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close search',
      child: Tooltip(
        message: 'Close',
        child: Material(
          color: MutandeColors.stone50,
          shape: const CircleBorder(
            side: BorderSide(color: MutandeColors.stone200),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox(
              width: HomeChrome.thumbHeight,
              height: HomeChrome.thumbHeight,
              child: Icon(
                CupertinoIcons.xmark,
                size: 13,
                color: MutandeColors.stone600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.recent, required this.onPick});

  final List<String> recent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Type to search collabs, threads, and contacts',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: MutandeColors.stone600,
                  height: 1.4,
                ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Recent',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: MutandeColors.stone500,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ...recent.map(
              (q) => InkWell(
                onTap: () => onPick(q),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        size: 16,
                        color: MutandeColors.stone400,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        q,
                        style: const TextStyle(
                          color: MutandeColors.stone800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HitList extends StatelessWidget {
  const _HitList({
    required this.hits,
    required this.grouped,
    required this.onPick,
  });

  final List<SearchHit> hits;
  final bool grouped;
  final ValueChanged<SearchHit> onPick;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    SearchHitKind? last;
    for (final hit in hits) {
      if (grouped && hit.kind != last) {
        last = hit.kind;
        final label = switch (hit.kind) {
          SearchHitKind.thread => 'Threads',
          SearchHitKind.collab => 'Collab',
          SearchHitKind.contact => 'Contacts',
        };
        final n = hits.where((h) => h.kind == hit.kind).length;
        rows.add(
          _SectionHeader(
            label: '$label · $n',
            padTop: rows.isEmpty,
          ),
        );
      }
      rows.add(_SearchHitRow(hit: hit, onTap: () => onPick(hit)));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (context, i) {
        if (rows[i] is _SectionHeader ||
            (i + 1 < rows.length && rows[i + 1] is _SectionHeader)) {
          return const SizedBox.shrink();
        }
        return const Divider(height: 1, color: MutandeColors.stone200);
      },
      itemBuilder: (context, i) => rows[i],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.padTop});

  final String label;
  final bool padTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6, top: padTop ? 4 : 18),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: MutandeColors.stone500,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SearchHitRow extends StatelessWidget {
  const _SearchHitRow({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final letter = hit.title.isNotEmpty ? hit.title[0].toUpperCase() : '?';
    final icon = switch (hit.kind) {
      SearchHitKind.thread => Icons.mail_outline,
      SearchHitKind.collab => Icons.view_kanban_outlined,
      SearchHitKind.contact => Icons.person_outline,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MutandeColors.stone50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MutandeColors.stone200),
              ),
              child: hit.hostSlug != null
                  ? AiHostIcon(hit.hostSlug!, size: 28, showPlate: false)
                  : hit.kind == SearchHitKind.contact
                      ? Text(
                          letter,
                          style: const TextStyle(
                            color: MutandeColors.stone500,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        )
                      : Icon(icon, size: 15, color: MutandeColors.stone500),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MutandeColors.stone800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (hit.subtitle != null && hit.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hit.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MutandeColors.stone500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
