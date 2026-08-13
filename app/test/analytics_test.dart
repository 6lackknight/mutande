import 'package:app/analytics_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop analytics events use desktop_ prefix', () {
    expect(AnalyticsEvent.appOpen, startsWith('desktop_'));
    expect(AnalyticsEvent.signInClick, startsWith('desktop_'));
    expect(AnalyticsEvent.homeReady, startsWith('desktop_'));
  });
}
