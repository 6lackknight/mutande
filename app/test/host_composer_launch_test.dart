import 'dart:io';

import 'package:app/services/host_composer_launch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cursor deep-link percent-encodes the prompt', () {
    expect(
      HostComposerLaunch.composerUrls(
        'cursor',
        'Use mutande to hand this off to @claude.',
      ),
      [
        'cursor://anysphere.cursor-deeplink/prompt?text=Use%20mutande%20to%20hand%20this%20off%20to%20%40claude.',
      ],
    );
  });

  test('chatgpt tries the new desktop scheme then classic', () {
    final urls = HostComposerLaunch.composerUrls('chatgpt', 'hi there');
    expect(urls, [
      'codex://new?prompt=hi%20there',
      'com.openai.chat://chatgpt.com/?prompt=hi%20there',
    ]);
  });

  test('claude prefills a new desktop chat', () {
    expect(HostComposerLaunch.composerUrls('claude', 'pong'), [
      'claude://claude.ai/new?q=pong',
    ]);
  });

  test('unknown hosts have no composer url', () {
    expect(HostComposerLaunch.canPrefill(null), isFalse);
    expect(HostComposerLaunch.canPrefill('warp'), isFalse);
    expect(HostComposerLaunch.displayName('cursor'), 'Cursor');
  });

  test('open returns prefilled on the first scheme that succeeds', () async {
    final tried = <String>[];
    final result = await HostComposerLaunch.open(
      slug: 'chatgpt',
      prompt: 'hi',
      run: (exe, args) async {
        tried.add('$exe ${args.join(' ')}');
        if (args.first.startsWith('codex://')) {
          return ProcessResult(0, 1, '', 'no handler');
        }
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(result, HostComposerOpenResult.prefilled);
    expect(tried.first, contains('codex://new?prompt=hi'));
    expect(tried.last, contains('com.openai.chat://chatgpt.com/?prompt=hi'));
  });

  test('open falls back to launching the Mac app', () async {
    final result = await HostComposerLaunch.open(
      slug: 'cursor',
      prompt: 'hi',
      run: (exe, args) async {
        if (args.contains('-a')) {
          expect(args, ['-a', 'Cursor']);
          return ProcessResult(0, 0, '', '');
        }
        return ProcessResult(0, 1, '', 'no handler');
      },
    );
    expect(
      result,
      Platform.isMacOS
          ? HostComposerOpenResult.appOpened
          : HostComposerOpenResult.failed,
    );
  });
}
