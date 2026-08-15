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

  group('personDisplayTitle', () {
    test('prefers hub display_name', () {
      expect(
        personDisplayTitle(
          displayName: 'Tawanda Brandon',
          handle: 'tawanda@tbhco',
        ),
        'Tawanda Brandon',
      );
    });

    test('falls back to handle local-part', () {
      expect(personDisplayTitle(handle: 'Orinea@tbhco'), 'Orinea');
      expect(personDisplayTitle(displayName: '  ', handle: 'bob@acme'), 'Bob');
      expect(
        personDisplayTitle(handle: 'tawanda.brandon@tbhco'),
        'Tawanda Brandon',
      );
    });

    test('initials from name or local-part', () {
      expect(personInitials('Tawanda Brandon'), 'TB');
      expect(personInitials('tawanda'), 'TA');
    });
  });
}
