import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/mutande_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FlutterErrorDetails _details([Object? exception]) {
  return FlutterErrorDetails(
    exception:
        exception ??
        StateError(
          "type 'Null' is not a subtype of type 'List<CollabArtifactView>' of 'function result'",
        ),
    library: 'widgets library',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(1280, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('exception line is first line only, no stack', () {
    expect(
      mutandeErrorExceptionLine(
        StateError(
          "type 'Null' is not a subtype of type 'List<CollabArtifactView>' of 'function result'",
        ),
      ),
      contains('List<CollabArtifactView>'),
    );
    expect(
      mutandeErrorExceptionLine(
        Exception('boom\n#0 foo.dart:1\n#1 bar.dart:2'),
      ),
      'boom',
    );
    final long = mutandeErrorExceptionLine(Exception('x' * 400));
    expect(long.length, lessThanOrEqualTo(181));
    expect(long.endsWith('…'), isTrue);
  });

  testWidgets('debug presentation is stone chrome with exception and Retry', (
    tester,
  ) async {
    var retries = 0;
    await _pump(
      tester,
      child: MutandeErrorWidget(details: _details(), onRetry: () => retries++),
    );
    expect(find.text('mutande'), findsOneWidget);
    expect(find.text("This view couldn't load"), findsOneWidget);
    expect(
      find.text(
        'mutande hit a snag drawing this screen. Your mail is still here.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('List<CollabArtifactView>'), findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('List<CollabArtifactView>'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('release presentation hides the exception line', (tester) async {
    await _pump(
      tester,
      child: MutandeErrorWidget(
        details: _details(),
        showException: false,
        onRetry: () {},
      ),
    );
    expect(find.text("This view couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    expect(find.textContaining('List<CollabArtifactView>'), findsNothing);
    expect(find.textContaining('function result'), findsNothing);
  });

  testWidgets('compact slot skips wordmark and keeps Retry', (tester) async {
    await _pump(
      tester,
      size: const Size(200, 160),
      child: MutandeErrorWidget(details: _details(), onRetry: () {}),
    );
    expect(find.text("This view couldn't load"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('mutande'), findsNothing);
    expect(find.text('Details'), findsNothing);
    expect(find.textContaining('List<CollabArtifactView>'), findsOneWidget);
    expect(
      find.text(
        'mutande hit a snag drawing this screen. Your mail is still here.',
      ),
      findsNothing,
    );
  });

  test('install builder returns mutande chrome', () {
    final previous = ErrorWidget.builder;
    try {
      MutandeErrorWidget.install();
      expect(ErrorWidget.builder(_details()), isA<MutandeErrorWidget>());
    } finally {
      ErrorWidget.builder = previous;
    }
  });

  testWidgets('builder output is mutande chrome, not the red screen', (
    tester,
  ) async {
    await _pump(tester, child: MutandeErrorWidget.builder(_details()));
    expect(find.byType(MutandeErrorWidget), findsOneWidget);
    expect(find.text("This view couldn't load"), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('List<CollabArtifactView>'), findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
