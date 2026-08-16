import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/mutande_stagger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {bool reduce = false}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: mutandeMaterialTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('first rows fade and rise; later ids skip after freeze', (
    WidgetTester tester,
  ) async {
    final ids = <String>['a', 'b'];
    late void Function(String) add;

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          add = (id) => setState(() => ids.add(id));
          return MutandeStaggerScope(
            child: Column(
              children: [
                for (final id in ids)
                  MutandeStaggerIn(key: ValueKey(id), id: id, child: Text(id)),
              ],
            ),
          );
        },
      ),
    );

    final firstOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('a'), matching: find.byType(Opacity)).first,
    );
    expect(firstOpacity.opacity, lessThan(0.2));

    await tester.pump(MutandeMotion.ui);
    final settled = tester.widget<Opacity>(
      find.ancestor(of: find.text('a'), matching: find.byType(Opacity)).first,
    );
    expect(settled.opacity, closeTo(1, 0.02));

    await tester.pump(); // flush freeze
    add('c');
    await tester.pump();

    expect(
      find.ancestor(of: find.text('c'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('disableAnimations shows rows at rest', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      MutandeStaggerScope(
        child: MutandeStaggerIn(id: 'a', child: const Text('a')),
      ),
      reduce: true,
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Transform && w.transform.getTranslation().y != 0,
      ),
      findsNothing,
    );
  });

  testWidgets('sectionStagger still rests under disableAnimations', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      MutandeStaggerScope(
        delay: MutandeStaggerScope.sectionStagger,
        child: const MutandeStaggerIn(id: 'a', child: Text('a')),
      ),
      reduce: true,
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
  });
}
