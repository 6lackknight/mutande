import 'package:app/services/version_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VersionCompare', () {
    test('normalize strips build metadata', () {
      expect(VersionCompare.normalize('2.0.1+20'), '2.0.1');
    });

    test('compare orders semver segments', () {
      expect(VersionCompare.compare('2.0.0', '2.0.1'), lessThan(0));
      expect(VersionCompare.compare('2.1.0', '2.0.9'), greaterThan(0));
      expect(VersionCompare.compare('2.0.1', '2.0.1'), 0);
    });

    test('isOlder detects stale builds', () {
      expect(VersionCompare.isOlder('2.0.0', '2.0.1'), isTrue);
      expect(VersionCompare.isOlder('2.0.1', '2.0.1'), isFalse);
      expect(VersionCompare.isOlder('2.0.2', '2.0.1'), isFalse);
    });
  });
}
