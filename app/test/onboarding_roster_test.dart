import 'dart:async';

import 'package:app/config/app_config.dart';
import 'package:app/screens/onboarding_flow_screen.dart';
import 'package:app/services/daemon_client.dart';
import 'package:app/services/daemon_errors.dart';
import 'fake_daemon_client.dart';
import 'package:app/services/first_run_store.dart';
import 'package:app/services/host_link_store.dart';
import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:app/widgets/onboarding_address_rail.dart';
import 'package:app/widgets/onboarding_chrome.dart';
import 'package:app/widgets/thread_skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('team roster shows avatar, name, handle, and you marker', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final daemon = rpcDaemon((method, params) async {
      if (method == 'get_status') {
        return {
          'configured': true,
          'signed_in': true,
          'handle': 'tawanda@tbhco',
          'hub_url': 'http://localhost:8000',
        };
      }
      if (method == 'list_contacts') {
        return {
          'contacts': [
            {
              'handle': 'tawanda@tbhco',
              'kind': 'org',
              'display_name': 'Tawanda Brandon',
              'avatar_url': 'https://cdn.example.test/t.jpg',
            },
            {
              'handle': 'orinea@tbhco',
              'kind': 'org',
              'display_name': 'Orinea',
            },
            {
              'handle': 'tawandadev@tbhco',
              'kind': 'org',
            },
          ],
        };
      }
      return {'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: OnboardingFlowScreen(
          config: const AppConfig(hubUrl: 'http://localhost:8000'),
          daemon: daemon,
          firstRunStore: FirstRunStore.memory(),
          hostLinkStore: HostLinkStore.memory(),
          onComplete: (_, _) {},
          initialStatus: const DaemonStatusResult(
            configured: true,
            signedIn: true,
            handle: 'tawanda@tbhco',
            hubUrl: 'http://localhost:8000',
          ),
          initialStep: OnboardingStep.team,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Tawanda Brandon'));

    expect(find.text('Tawanda Brandon'), findsOneWidget);
    expect(find.text('tawanda@tbhco'), findsWidgets);
    expect(find.text('you'), findsOneWidget);
    expect(find.text('Orinea'), findsOneWidget);
    expect(find.text('orinea@tbhco'), findsOneWidget);
    expect(find.text('Tawandadev'), findsOneWidget);
    expect(find.text('tawandadev@tbhco'), findsOneWidget);
    expect(find.byType(PersonAvatar), findsNWidgets(3));
    expect(find.text('Two teammates can already reach you.'), findsOneWidget);
  });

  testWidgets('team roster loading keeps onboarding chrome', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'get_status') {
        return {
          'configured': true,
          'signed_in': true,
          'handle': 'tawanda@tbhco',
          'hub_url': 'http://localhost:8000',
        };
      }
      if (method == 'list_contacts') {
        await gate.future;
        return {
          'contacts': [
            {
              'handle': 'tawanda@tbhco',
              'kind': 'org',
              'display_name': 'Tawanda Brandon',
            },
          ],
        };
      }
      return {'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OnboardingFlowScreen(
            config: const AppConfig(hubUrl: 'http://localhost:8000'),
            daemon: daemon,
            firstRunStore: FirstRunStore.memory(),
            hostLinkStore: HostLinkStore.memory(),
            onComplete: (_, _) {},
            initialStatus: const DaemonStatusResult(
              configured: true,
              signedIn: true,
              handle: 'tawanda@tbhco',
              hubUrl: 'http://localhost:8000',
            ),
            initialStep: OnboardingStep.team,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Your team.'), findsOneWidget);
    expect(find.byType(OnboardingRosterSkeleton), findsOneWidget);
    expect(find.text('Tawanda Brandon'), findsNothing);

    gate.complete();
    await _pumpUntil(tester, find.text('Tawanda Brandon'));
    expect(find.byType(OnboardingRosterSkeleton), findsNothing);
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Tawanda Brandon'), findsOneWidget);
  });

  testWidgets('connect host loading keeps onboarding chrome', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final gate = Completer<void>();
    final daemon = rpcDaemon((method, params) async {
      if (method == 'get_status') {
        return {
          'configured': true,
          'signed_in': true,
          'handle': 'tawanda@tbhco',
          'hub_url': 'http://localhost:8000',
        };
      }
      if (method == 'detect_ai_hosts') {
        await gate.future;
        return {
          'hosts': [
            {'host': 'cursor', 'installed': true, 'config_present': false},
          ],
        };
      }
      if (method == 'list_agents') {
        await gate.future;
        return {'agents': <Object?>[]};
      }
      return {'ok': true};
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: mutandeMaterialTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: OnboardingFlowScreen(
            config: const AppConfig(hubUrl: 'http://localhost:8000'),
            daemon: daemon,
            firstRunStore: FirstRunStore.memory(),
            hostLinkStore: HostLinkStore.memory(),
            onComplete: (_, _) {},
            initialStatus: const DaemonStatusResult(
              configured: true,
              signedIn: true,
              handle: 'tawanda@tbhco',
              hubUrl: 'http://localhost:8000',
            ),
            initialStep: OnboardingStep.connect,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Pick a host to connect.'), findsOneWidget);
    expect(find.byType(OnboardingHostSkeleton), findsOneWidget);

    gate.complete();
    await _pumpUntil(tester, find.text('Cursor'));
    expect(find.byType(OnboardingHostSkeleton), findsNothing);
    expect(find.byType(OnboardingAddressRail), findsOneWidget);
    expect(find.text('Pick a host to connect.'), findsOneWidget);
  });
}
