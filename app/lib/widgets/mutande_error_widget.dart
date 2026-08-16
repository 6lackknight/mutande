import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../theme/mutande_macos_theme.dart';

/// Replaces Flutter's red [ErrorWidget] for widget-build failures.
///
/// Distinct from [DaemonErrorScreen] (courier / hub transport). This is the
/// last-resort chrome when a subtree throws during build.
class MutandeErrorWidget extends StatelessWidget {
  const MutandeErrorWidget({
    super.key,
    required this.details,
    this.onRetry,
    this.showException = !kReleaseMode,
  });

  final FlutterErrorDetails details;
  final VoidCallback? onRetry;

  /// Debug / profile: one exception line. Release: calm copy only.
  final bool showException;

  static VoidCallback? _retryHandler;

  /// App-wide builder. Call from `main` (not widget tests).
  static void install({VoidCallback? onRetry}) {
    if (onRetry != null) _retryHandler = onRetry;
    ErrorWidget.builder = builder;
  }

  /// Retry remounts the shell. Does not touch [ErrorWidget.builder].
  static void bindRetry(VoidCallback? onRetry) {
    _retryHandler = onRetry;
  }

  static Widget builder(FlutterErrorDetails details) {
    return MutandeErrorWidget(details: details, onRetry: _retryHandler);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: mutandeMaterialTheme(),
      child: Material(
        color: MutandeColors.stone100,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 220 || constraints.maxWidth < 280;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MutandeMotion.of(context, MutandeMotion.ui),
              curve: MutandeMotion.easeOut,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: compact
                  ? _CompactBody(
                      exceptionLine: showException
                          ? mutandeErrorExceptionLine(details.exception)
                          : null,
                      onRetry: onRetry,
                    )
                  : _SpaciousBody(
                      exceptionLine: showException
                          ? mutandeErrorExceptionLine(details.exception)
                          : null,
                      onRetry: onRetry,
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// First line of [exception], truncated. Never a stack dump.
String mutandeErrorExceptionLine(Object exception) {
  var msg = exception.toString().trim();
  final newline = msg.indexOf('\n');
  if (newline >= 0) msg = msg.substring(0, newline).trim();
  for (final prefix in ['Exception: ', 'Error: ']) {
    if (msg.startsWith(prefix)) {
      msg = msg.substring(prefix.length);
    }
  }
  if (msg.length > 180) {
    msg = '${msg.substring(0, 177)}…';
  }
  return msg;
}

class _SpaciousBody extends StatefulWidget {
  const _SpaciousBody({this.exceptionLine, this.onRetry});

  final String? exceptionLine;
  final VoidCallback? onRetry;

  @override
  State<_SpaciousBody> createState() => _SpaciousBodyState();
}

class _SpaciousBodyState extends State<_SpaciousBody> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final exceptionLine = widget.exceptionLine;
    final onRetry = widget.onRetry;
    final hasDetails = exceptionLine != null && exceptionLine.isNotEmpty;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: MutandeColors.bronze.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 28),
                Text(
                  'mutande',
                  style: text.headlineSmall?.copyWith(
                    color: MutandeColors.stone800,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "This view couldn't load",
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    color: MutandeColors.stone800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'mutande hit a snag drawing this screen. Your mail is still here.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: MutandeColors.stone600,
                    height: 1.45,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ),
                ],
                if (hasDetails) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        setState(() => _detailsOpen = !_detailsOpen),
                    style: TextButton.styleFrom(
                      foregroundColor: MutandeColors.stone500,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(_detailsOpen ? 'Hide details' : 'Details'),
                  ),
                  if (_detailsOpen)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                        exceptionLine,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: MutandeColors.stone400,
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({this.exceptionLine, this.onRetry});

  final String? exceptionLine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 22,
              color: MutandeColors.bronze.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 8),
            Text(
              "This view couldn't load",
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                color: MutandeColors.stone800,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (exceptionLine != null && exceptionLine!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                exceptionLine!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: MutandeColors.stone400,
                  height: 1.35,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: MutandeColors.bronze,
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
