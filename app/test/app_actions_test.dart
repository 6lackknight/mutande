import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/app_actions.dart';

void main() {
  test('requestConnectHosts bumps tick', () {
    final before = AppActions.connectHostsTick.value;
    var heard = false;
    void listener() => heard = true;
    AppActions.connectHostsTick.addListener(listener);
    AppActions.requestConnectHosts();
    AppActions.connectHostsTick.removeListener(listener);
    expect(AppActions.connectHostsTick.value, before + 1);
    expect(heard, isTrue);
  });
}
