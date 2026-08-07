import 'package:flutter_test/flutter_test.dart';
import 'package:app/util/address_display.dart';

void main() {
  group('formatMailAddress', () {
    test('lowercases full handle and agent slug', () {
      expect(
        formatMailAddress('Alice@Acme/Cursor'),
        'alice@acme/cursor',
      );
    });

    test('self shorthand is lowercase', () {
      expect(
        formatMailAddress('Alice@Acme/Cursor', myHandle: 'alice@acme'),
        '@cursor',
      );
      expect(
        formatMailAddress('alice@acme/CURSOR', myHandle: 'Alice@Acme'),
        '@cursor',
      );
    });

    test('strips /default case-insensitively', () {
      expect(
        formatMailAddress('alice@acme/Default', myHandle: 'alice@acme'),
        'alice@acme',
      );
      expect(formatMailAddress('Alice@Acme/DEFAULT'), 'alice@acme');
    });

    test('preserves @all and broadcast lowercase', () {
      expect(formatMailAddress('@All'), '@all');
      expect(formatMailAddress('@All@Acme'), '@all@acme');
    });

    test('bare handle lowercase', () {
      expect(
        formatMailAddress('Alice@Acme', myHandle: 'alice@acme'),
        'alice@acme',
      );
    });
  });
}
