import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/home_chrome_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  bool reduce = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

Finder get _thumb => find.byKey(HomeChromeStrip.thumbKey);

void main() {
  testWidgets('renders Threads · Collab · Network', (tester) async {
    await _pump(
      tester,
      child: HomeChromeStrip(tab: 0, onTab: (_) {}),
    );
    await tester.pump();

    expect(find.text('Threads'), findsOneWidget);
    expect(find.text('Collab'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);
    expect(_thumb, findsOneWidget);
  });

  testWidgets('thumb slides to Collab instead of teleporting', (tester) async {
    var tab = 0;
    await _pump(
      tester,
      child: StatefulBuilder(
        builder: (context, setState) {
          return HomeChromeStrip(
            tab: tab,
            onTab: (i) => setState(() => tab = i),
          );
        },
      ),
    );
    await tester.pump(); // equalize segment widths

    final origin = tester.getTopLeft(_thumb).dx;
    expect(tester.getTopLeft(_thumb).dx, closeTo(origin, 0.5));

    await tester.tap(find.text('Collab'));
    await tester.pump();

    expect(
      tester.getTopLeft(_thumb).dx,
      closeTo(origin, 0.5),
      reason: 'first animation frame stays at Threads',
    );

    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getTopLeft(_thumb).dx;
    expect(mid, greaterThan(origin + 2));

    await tester.pump(MutandeMotion.ui);
    final rest = tester.getTopLeft(_thumb).dx;
    expect(rest, greaterThan(mid));

    final collabLeft = tester.getTopLeft(find.text('Collab')).dx;
    final thumbLeft = tester.getTopLeft(_thumb).dx;
    final thumbRight = tester.getBottomRight(_thumb).dx;
    expect(thumbLeft, lessThan(collabLeft));
    expect(thumbRight, greaterThan(collabLeft));
  });

  testWidgets('disableAnimations snaps the thumb', (tester) async {
    var tab = 0;
    await _pump(
      tester,
      reduce: true,
      child: StatefulBuilder(
        builder: (context, setState) {
          return HomeChromeStrip(
            tab: tab,
            onTab: (i) => setState(() => tab = i),
          );
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Network'));
    await tester.pump();

    final thumbLeft = tester.getTopLeft(_thumb).dx;
    final networkLeft = tester.getTopLeft(find.text('Network')).dx;
    final thumbRight = tester.getBottomRight(_thumb).dx;
    expect(thumbLeft, lessThan(networkLeft));
    expect(thumbRight, greaterThan(networkLeft));
  });
}
