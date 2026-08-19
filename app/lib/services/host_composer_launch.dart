import 'dart:io';

/// Outcome of asking the OS to open a host with a prompt in the composer.
enum HostComposerOpenResult {
  /// Desktop URL scheme opened; prompt should be sitting in the composer.
  prefilled,

  /// App came forward, but the composer was not prefilled. Prompt is on the
  /// clipboard for a manual paste.
  appOpened,

  /// Nothing launched.
  failed,
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Opens Cursor / ChatGPT / Claude with a prompt in the composer.
///
/// Hosts do not auto-send. The human still reviews and hits send.
abstract final class HostComposerLaunch {
  /// Short app name for headings and the Open CTA (`Cursor`, not `cursor`).
  static String? displayName(String? slug) {
    switch ((slug ?? '').trim().toLowerCase()) {
      case 'cursor':
        return 'Cursor';
      case 'chatgpt':
        return 'ChatGPT';
      case 'chatgpt-web':
        return 'ChatGPT Web';
      case 'claude':
        return 'Claude';
      case 'claude-web':
        return 'Claude Web';
      default:
        return null;
    }
  }

  static bool canPrefill(String? slug) =>
      composerUrls(slug ?? '', 'x').isNotEmpty;

  /// Desktop composer or web home — enough to show an Open CTA.
  static bool canOpen(String? slug) =>
      canPrefill(slug) || webHomeUrls(slug ?? '').isNotEmpty;

  /// ChatGPT / Claude in the browser (hosted MCP). Prompt stays on the clipboard.
  static List<String> webHomeUrls(String slug) {
    switch (slug.trim().toLowerCase()) {
      case 'chatgpt-web':
        return const ['https://chatgpt.com'];
      case 'claude-web':
        return const ['https://claude.ai'];
      default:
        return const [];
    }
  }

  /// Documented composer deep links. Values are percent-encoded.
  static List<String> composerUrls(String slug, String prompt) {
    final q = Uri.encodeComponent(prompt);
    switch (slug.trim().toLowerCase()) {
      case 'cursor':
        return ['cursor://anysphere.cursor-deeplink/prompt?text=$q'];
      case 'chatgpt':
        return [
          'codex://new?prompt=$q',
          'com.openai.chat://chatgpt.com/?prompt=$q',
        ];
      case 'claude':
        return ['claude://claude.ai/new?q=$q'];
      default:
        return [];
    }
  }

  static List<String> macAppNames(String slug) {
    switch (slug.trim().toLowerCase()) {
      case 'cursor':
        return const ['Cursor'];
      case 'chatgpt':
        return const ['ChatGPT', 'Codex'];
      case 'claude':
        return const ['Claude'];
      default:
        return const [];
    }
  }

  static Future<HostComposerOpenResult> open({
    required String slug,
    required String prompt,
    ProcessRunner? run,
  }) async {
    final urls = composerUrls(slug, prompt);
    if (run == null && Platform.environment.containsKey('FLUTTER_TEST')) {
      if (urls.isNotEmpty) return HostComposerOpenResult.prefilled;
      if (webHomeUrls(slug).isNotEmpty) return HostComposerOpenResult.appOpened;
      return HostComposerOpenResult.failed;
    }
    final runner = run ?? (exe, args) => Process.run(exe, args);
    for (final url in urls) {
      if (await _openUrl(url, runner)) return HostComposerOpenResult.prefilled;
    }
    for (final url in webHomeUrls(slug)) {
      if (await _openUrl(url, runner)) return HostComposerOpenResult.appOpened;
    }
    if (Platform.isMacOS) {
      for (final app in macAppNames(slug)) {
        final result = await runner('open', ['-a', app]);
        if (result.exitCode == 0) return HostComposerOpenResult.appOpened;
      }
    }
    return HostComposerOpenResult.failed;
  }

  static Future<bool> _openUrl(String url, ProcessRunner runner) async {
    final ProcessResult result;
    if (Platform.isMacOS) {
      result = await runner('open', [url]);
    } else if (Platform.isWindows) {
      result = await runner('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isLinux) {
      result = await runner('xdg-open', [url]);
    } else {
      return false;
    }
    return result.exitCode == 0;
  }
}
