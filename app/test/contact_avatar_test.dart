import 'package:app/theme/mutande_macos_theme.dart';
import 'package:app/widgets/contact_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personMarkPlate is stable and inks self', () {
    expect(
      personMarkPlate('orinea@tbhco').fill,
      personMarkPlate('orinea@tbhco').fill,
    );
    final fills = {
      personMarkPlate('tawanda@tbhco').fill,
      personMarkPlate('orinea@tbhco').fill,
      personMarkPlate('tawandadev@tbhco').fill,
      personMarkPlate('bob@acme').fill,
    };
    expect(fills.length, greaterThan(1));
    final self = personMarkPlate('tawanda@tbhco', isSelf: true);
    expect(self.fill, MutandeColors.stone800);
    expect(self.ink, MutandeColors.stone50);
  });
}
