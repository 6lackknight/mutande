import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/daemon_client.dart';
import '../theme/mutande_macos_theme.dart';

/// Quiet file rows under a thread message — preview popular types in-app.
class MessageAttachments extends StatelessWidget {
  const MessageAttachments({super.key, required this.resources});

  final List<BundleResourceView> resources;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < resources.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _AttachmentRow(resource: resources[i]),
        ],
      ],
    );
  }
}

Future<void> openAttachmentPath(String path) async {
  await Process.run('open', [path]);
}

Future<void> revealAttachmentPath(String path) async {
  await Process.run('open', ['-R', path]);
}

/// Write inline `content` to a temp file so Open / Reveal work like path-backed blobs.
Future<String?> materializeInlineAttachment(BundleResourceView resource) async {
  final content = resource.content;
  if (content == null || content.isEmpty) return null;
  final safe = resource.name.replaceAll(RegExp(r'[/\\]'), '_');
  final name = safe.trim().isEmpty ? 'attachment.txt' : safe.trim();
  final dir = await Directory.systemTemp.createTemp('mutande-attach-');
  final file = File('${dir.path}/$name');
  await file.writeAsString(content);
  return file.path;
}

class _AttachmentRow extends StatefulWidget {
  const _AttachmentRow({required this.resource});

  final BundleResourceView resource;

  @override
  State<_AttachmentRow> createState() => _AttachmentRowState();
}

class _AttachmentRowState extends State<_AttachmentRow> {
  bool _expanded = false;

  BundleResourceView get r => widget.resource;

  bool get _canInlinePreview {
    if (!r.isAvailable) return false;
    if (r.isImage && r.hasPath) return true;
    if (r.isVideo && r.hasPath) return true;
    if (r.isText && (r.hasContent || r.hasPath)) return true;
    return false;
  }

  Future<void> _onPrimaryTap() async {
    if (!r.isAvailable) return;
    if (_canInlinePreview) {
      setState(() => _expanded = !_expanded);
      return;
    }
    if (r.hasPath) {
      await openAttachmentPath(r.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      r.kindLabel,
      if (r.sizeLabel != null) r.sizeLabel!,
    ].join(' · ');
    final unavailable = !r.isAvailable;
    final borderColor = unavailable
        ? MutandeColors.stone200
        : const Color(0xFFD6D3D1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: MutandeColors.stone50,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: unavailable ? null : _onPrimaryTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  _FileGlyph(resource: r, unavailable: unavailable),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: unavailable
                                    ? MutandeColors.stone500
                                    : MutandeColors.stone800,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unavailable
                              ? 'Unavailable on this device — ask to re-send'
                              : meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: unavailable
                                    ? MutandeColors.stone400
                                    : MutandeColors.stone500,
                                height: 1.25,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (!unavailable) ...[
                    if (_canInlinePreview)
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: MutandeColors.stone400,
                      )
                    else if (r.hasPath)
                      IconButton(
                        tooltip: 'Open',
                        onPressed: () => openAttachmentPath(r.path!),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        color: MutandeColors.stone500,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    if (r.hasPath)
                      IconButton(
                        tooltip: 'Reveal in Finder',
                        onPressed: () => revealAttachmentPath(r.path!),
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        color: MutandeColors.stone500,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      )
                    else if (r.hasContent) ...[
                      IconButton(
                        tooltip: 'Open',
                        onPressed: () async {
                          final path = await materializeInlineAttachment(r);
                          if (path != null) await openAttachmentPath(path);
                        },
                        icon: const Icon(Icons.open_in_new, size: 16),
                        color: MutandeColors.stone500,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reveal in Finder',
                        onPressed: () async {
                          final path = await materializeInlineAttachment(r);
                          if (path != null) await revealAttachmentPath(path);
                        },
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        color: MutandeColors.stone500,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_expanded && _canInlinePreview) ...[
          const SizedBox(height: 8),
          _AttachmentPreview(resource: r),
        ],
      ],
    );
  }
}

class _FileGlyph extends StatelessWidget {
  const _FileGlyph({required this.resource, required this.unavailable});

  final BundleResourceView resource;
  final bool unavailable;

  IconData get _icon {
    if (resource.isImage) return Icons.image_outlined;
    if (resource.isVideo) return Icons.videocam_outlined;
    if (resource.isPdf) return Icons.picture_as_pdf_outlined;
    if (resource.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: unavailable ? MutandeColors.stone100 : const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: Icon(
        _icon,
        size: 18,
        color: unavailable ? MutandeColors.stone400 : MutandeColors.stone600,
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.resource});

  final BundleResourceView resource;

  @override
  Widget build(BuildContext context) {
    if (resource.isImage && resource.hasPath) {
      return _ImagePreview(path: resource.path!);
    }
    if (resource.isVideo && resource.hasPath) {
      return _VideoPreview(path: resource.path!, name: resource.name);
    }
    if (resource.isText) {
      return _TextPreview(resource: resource);
    }
    return const SizedBox.shrink();
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return _PreviewShell(
        child: Text(
          'File missing on disk',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: MutandeColors.stone500,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return _PreviewShell(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Could not preview image',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: MutandeColors.stone500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final file = File(widget.path);
    if (!file.existsSync()) {
      setState(() => _error = 'File missing on disk');
      return;
    }
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onVideoTick);
      setState(() => _controller = c);
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = e);
    }
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _controller;
    c?.removeListener(_onVideoTick);
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _PreviewShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not play in-app',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: MutandeColors.stone600,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => openAttachmentPath(widget.path),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open with system player'),
              style: TextButton.styleFrom(
                foregroundColor: MutandeColors.stone600,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return _PreviewShell(
        child: SizedBox(
          height: 120,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MutandeColors.stone400,
              ),
            ),
          ),
        ),
      );
    }
    return _PreviewShell(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(c),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (c.value.isPlaying) {
                            c.pause();
                          } else {
                            c.play();
                          }
                        });
                      },
                      child: AnimatedOpacity(
                        opacity: c.value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xCC0C0A09),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: c.value.isPlaying ? 'Pause' : 'Play',
                  onPressed: () {
                    setState(() {
                      if (c.value.isPlaying) {
                        c.pause();
                      } else {
                        c.play();
                      }
                    });
                  },
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 18,
                  ),
                  color: MutandeColors.stone600,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: MutandeColors.stone500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => openAttachmentPath(widget.path),
                  style: TextButton.styleFrom(
                    foregroundColor: MutandeColors.stone600,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.resource});

  final BundleResourceView resource;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  String? _text;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = widget.resource;
    try {
      String text;
      if (r.hasContent) {
        text = r.content!;
      } else if (r.hasPath) {
        text = await File(r.path!).readAsString();
      } else {
        text = '';
      }
      // Cap preview so giant files don't blow the pane.
      const maxChars = 24000;
      if (text.length > maxChars) {
        text = '${text.substring(0, maxChars)}\n\n… truncated';
      }
      if (mounted) {
        setState(() {
          _text = text;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _PreviewShell(
        child: Text(
          'Loading…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: MutandeColors.stone400,
          ),
        ),
      );
    }
    if (_error != null || _text == null) {
      return _PreviewShell(
        child: Text(
          'Could not read text',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: MutandeColors.stone500,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return _PreviewShell(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: SelectableText(
            _text!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: MutandeColors.stone800,
              height: 1.45,
              fontFamily: 'Menlo',
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MutandeColors.stone50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MutandeColors.stone200),
      ),
      child: child,
    );
  }
}
