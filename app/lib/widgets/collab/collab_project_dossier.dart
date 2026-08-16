import 'package:flutter/material.dart';

import '../../services/daemon_client.dart';
import '../../theme/mutande_macos_theme.dart';
import '../../util/address_display.dart';
import '../../util/clock_format.dart';
import '../message_attachments.dart';
import '../thinking_orb.dart';
import 'collab_overview.dart';

/// Artifact-led collab body: instructions, produced files, retained memory,
/// current position, then the board. Global app chrome stays outside.
class CollabProjectDossier extends StatelessWidget {
  const CollabProjectDossier({
    super.key,
    required this.collab,
    List<CollabArtifactView>? artifacts,
    required this.artifactsLoading,
    required this.board,
    required this.onOpenBrain,
    required this.onOpenCard,
    this.myHandle,
  }) : _artifacts = artifacts;

  final CollabDetail collab;
  final List<CollabArtifactView>? _artifacts;
  List<CollabArtifactView> get artifacts => _artifacts ?? const [];
  final bool artifactsLoading;
  final Widget board;
  final VoidCallback onOpenBrain;
  final ValueChanged<String> onOpenCard;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final overview = CollabOverview.fromDetail(collab);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          sliver: SliverToBoxAdapter(
            child: _ProjectInstructions(
              collab: collab,
              onOpenBrain: onOpenBrain,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 22)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final artifactDossier = _ArtifactDossier(
                  artifacts: artifacts,
                  loading: artifactsLoading,
                  onOpenCard: onOpenCard,
                );
                final memory = _MemoryLedger(
                  learnings: collab.learnings,
                  onOpenBrain: onOpenBrain,
                  myHandle: myHandle,
                );
                if (constraints.maxWidth < 760) {
                  return Column(
                    children: [
                      if (artifactsLoading || artifacts.isNotEmpty) ...[
                        artifactDossier,
                        const SizedBox(height: 24),
                      ],
                      memory,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (artifactsLoading || artifacts.isNotEmpty) ...[
                      Expanded(flex: 3, child: artifactDossier),
                      const SizedBox(width: 36),
                    ],
                    Expanded(flex: 2, child: memory),
                  ],
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverToBoxAdapter(
            child: _CurrentPosition(
              overview: overview,
              collab: collab,
              myHandle: myHandle,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: SizedBox(height: 420, child: board)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _ProjectInstructions extends StatelessWidget {
  const _ProjectInstructions({required this.collab, required this.onOpenBrain});

  final CollabDetail collab;
  final VoidCallback onOpenBrain;

  @override
  Widget build(BuildContext context) {
    final instructions = collab.instructions?.trim();
    final hasInstructions = instructions != null && instructions.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      color: MutandeColors.stone800,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROJECT INSTRUCTIONS',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: MutandeColors.stone400,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  hasInstructions
                      ? instructions
                      : 'No standing instructions yet.',
                  style: TextStyle(
                    fontSize: hasInstructions ? 17 : 15,
                    height: 1.4,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone50,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasInstructions
                      ? 'Standing context agents read before taking work.'
                      : collab.isE2e
                      ? 'E2E instructions remain sealed to steerer devices.'
                      : 'Give people and agents the goal, constraints, and working agreement.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: MutandeColors.stone400,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onOpenBrain,
                  style: TextButton.styleFrom(
                    foregroundColor: MutandeColors.stone50,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                  ),
                  child: Text(hasInstructions ? 'Open Brain' : 'Add in Brain'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactDossier extends StatelessWidget {
  const _ArtifactDossier({
    required this.artifacts,
    required this.loading,
    required this.onOpenCard,
  });

  final List<CollabArtifactView> artifacts;
  final bool loading;
  final ValueChanged<String> onOpenCard;

  @override
  Widget build(BuildContext context) {
    if (!loading && artifacts.isEmpty) return const SizedBox.shrink();
    final visible = artifacts.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: 'ARTIFACTS',
          title: 'Files and links',
          body:
              'Attached files stay on this collab; links point at a resource or deployment.',
          trailing: loading
              ? const MutandeOrb.loading(
                  semanticLabel: 'Opening collab artifacts',
                )
              : Text(
                  '${artifacts.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: MutandeColors.stone500,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        if (!loading)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final artifact in visible)
                _ArtifactChip(
                  artifact: artifact,
                  onOpenCard: artifact.threadId.trim().isEmpty
                      ? null
                      : () => onOpenCard(artifact.threadId),
                ),
            ],
          ),
      ],
    );
  }
}

class _ArtifactChip extends StatefulWidget {
  const _ArtifactChip({required this.artifact, this.onOpenCard});

  final CollabArtifactView artifact;
  final VoidCallback? onOpenCard;

  @override
  State<_ArtifactChip> createState() => _ArtifactChipState();
}

class _ArtifactChipState extends State<_ArtifactChip> {
  bool _preview = false;

  CollabArtifactView get artifact => widget.artifact;

  Future<void> _openFile() async {
    var path = artifact.resource.path;
    if ((path == null || path.trim().isEmpty) && artifact.resource.hasContent) {
      path = await materializeInlineAttachment(artifact.resource);
    }
    if (path != null && path.trim().isNotEmpty) {
      await openAttachmentPath(path);
    }
  }

  Future<void> _onTap() async {
    if (artifact.isLink) {
      if (artifact.url.trim().isEmpty) return;
      await openExternalUrl(artifact.url);
      return;
    }
    if (_canPreview) {
      setState(() => _preview = !_preview);
      return;
    }
    await _openFile();
  }

  bool get _canPreview {
    final r = artifact.resource;
    if (!r.isAvailable) return false;
    if (r.isImage && r.hasPath) return true;
    if (r.isVideo && r.hasPath) return true;
    if (r.isText && (r.hasContent || r.hasPath)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isLink = artifact.isLink;
    final when = formatRelativeTime(artifact.createdAt);
    final handle = formatMailAddress(artifact.fromHandle);
    final urlShown =
        isLink &&
            artifact.url.trim().isNotEmpty &&
            !isHubCourierUrl(artifact.url)
        ? artifact.url
        : null;
    final meta = [
      if (!isLink && artifact.resource.sizeLabel != null)
        artifact.resource.sizeLabel!,
      if (handle.isNotEmpty) handle,
      if (when.isNotEmpty) when,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: [
            urlShown ?? artifact.title,
            if (widget.onOpenCard != null) artifact.cardTitle,
          ].join('\n'),
          child: GestureDetector(
            onLongPress: widget.onOpenCard,
            child: InputChip(
              avatar: Icon(
                isLink ? Icons.link : _fileIcon(artifact.resource),
                size: 16,
              ),
              label: Text(artifact.title),
              onPressed:
                  (isLink && artifact.url.trim().isNotEmpty) ||
                      artifact.resource.isAvailable
                  ? _onTap
                  : widget.onOpenCard,
            ),
          ),
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(
              meta,
              style: const TextStyle(
                fontSize: 10,
                color: MutandeColors.stone400,
              ),
            ),
          ),
        if (_preview)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 280,
              child: MessageAttachments(resources: [artifact.resource]),
            ),
          ),
      ],
    );
  }

  IconData _fileIcon(BundleResourceView resource) {
    if (resource.isImage) return Icons.image_outlined;
    if (resource.isVideo) return Icons.movie_outlined;
    if (resource.isPdf) return Icons.picture_as_pdf_outlined;
    if (resource.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _MemoryLedger extends StatelessWidget {
  const _MemoryLedger({
    required this.learnings,
    required this.onOpenBrain,
    this.myHandle,
  });

  final List<CollabLearningView> learnings;
  final VoidCallback onOpenBrain;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final latest = learnings.reversed.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          eyebrow: 'BRAIN',
          title: 'What this collab remembers',
          body: 'Curated one-liners, not an activity log.',
          trailing: TextButton(
            onPressed: onOpenBrain,
            child: const Text('Open Brain'),
          ),
        ),
        const SizedBox(height: 12),
        if (latest.isEmpty)
          const Text(
            'No retained learnings yet.',
            style: TextStyle(fontSize: 12, color: MutandeColors.stone400),
          )
        else
          for (var i = 0; i < latest.length; i++)
            _LearningRow(
              learning: latest[i],
              myHandle: myHandle,
              last: i == latest.length - 1,
            ),
      ],
    );
  }
}

class _LearningRow extends StatelessWidget {
  const _LearningRow({
    required this.learning,
    required this.last,
    this.myHandle,
  });

  final CollabLearningView learning;
  final bool last;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final notes = learning.notes?.trim();
    final who = formatMailAddress(learning.fromHandle, myHandle: myHandle);
    final when = formatRelativeTime(learning.createdAt);
    return Container(
      padding: const EdgeInsets.only(bottom: 11),
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: MutandeColors.stone200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notes?.isNotEmpty == true ? notes! : 'Sealed learning',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: MutandeColors.stone600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [who, if (when.isNotEmpty) when].join(' · '),
            style: const TextStyle(fontSize: 10, color: MutandeColors.stone400),
          ),
        ],
      ),
    );
  }
}

class _CurrentPosition extends StatelessWidget {
  const _CurrentPosition({
    required this.overview,
    required this.collab,
    this.myHandle,
  });

  final CollabOverview overview;
  final CollabDetail collab;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final last = formatRelativeTime(overview.lastActivityAt);
    return Row(
      children: [
        Expanded(
          child: _SectionHeading(
            eyebrow: 'CURRENT POSITION',
            title: 'Work in motion',
            body: [
              '${overview.open} open',
              '${overview.doing} in Doing',
              '${overview.needsYou} awaiting you',
              if (last.isNotEmpty) 'latest $last',
            ].join(' · '),
          ),
        ),
        const SizedBox(width: 20),
        _WorkingGroupSummary(collab: collab, myHandle: myHandle),
      ],
    );
  }
}

class _WorkingGroupSummary extends StatelessWidget {
  const _WorkingGroupSummary({required this.collab, this.myHandle});

  final CollabDetail collab;
  final String? myHandle;

  @override
  Widget build(BuildContext context) {
    final humanLabels = collab.steererHandles
        .take(3)
        .map((h) => formatMailAddress(h, myHandle: myHandle))
        .join(', ');
    return Tooltip(
      message: [
        if (humanLabels.isNotEmpty) 'Humans steering: $humanLabels',
        if (collab.roster.isNotEmpty)
          'Agents working: ${collab.roster.map((r) => formatMailAddress(r.address, myHandle: myHandle)).join(', ')}',
      ].join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: MutandeColors.stone200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${collab.steererHandles.length} humans steering · '
          '${collab.roster.length} agents working',
          style: const TextStyle(fontSize: 10.5, color: MutandeColors.stone500),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.body,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.75,
                  fontWeight: FontWeight.w700,
                  color: MutandeColors.stone400,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            height: 1.15,
            letterSpacing: -0.35,
            fontWeight: FontWeight.w600,
            color: MutandeColors.stone800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          body,
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: MutandeColors.stone500,
          ),
        ),
      ],
    );
  }
}
