/// One foreground service, two owners: push keeps a connection open for days, a voice call needs the microphone for
/// minutes. The call's notification and type win while it runs; push's come back after, and the service never stops
/// in between.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/data/push/foreground_arbiter.dart';

final class _Driver implements ForegroundDriver {
  final log = <String>[];
  final told = <Map<String, Object?>>[];
  bool startWorks = true;
  bool retypeWorks = true;

  @override
  Future<bool> start({
    required Set<ServiceType> types,
    required ServiceNotice notice,
    required ServiceOwner channel,
    required bool persistent,
  }) async {
    log.add(
      'start ${_t(types)} "${notice.title}" ${channel.name} persistent=$persistent',
    );
    return startWorks;
  }

  @override
  Future<void> update(ServiceNotice notice, {required bool persistent}) async {
    log.add('update "${notice.title}" persistent=$persistent');
  }

  @override
  Future<bool> retype(Set<ServiceType> types) async {
    log.add('retype ${_t(types)}${retypeWorks ? '' : ' (refused)'}');
    return retypeWorks;
  }

  @override
  Future<void> stop() async => log.add('stop');

  @override
  void tell(Map<String, Object?> message) => told.add(message);

  static String _t(Set<ServiceType> types) =>
      (types.map((t) => t.name).toList()..sort()).join('+');
}

const _push = ServiceNotice(title: 'Iris is connected', text: '');
const _call = ServiceNotice(
  title: 'Call with Iris',
  text: 'Listening',
  buttons: [ServiceButton('mute', 'Mute'), ServiceButton('end', 'End')],
);
const _call2 = ServiceNotice(title: 'Call with Iris', text: 'Speaking');

void main() {
  late _Driver driver;
  late ForegroundArbiter arbiter;

  setUp(() {
    driver = _Driver();
    arbiter = ForegroundArbiter(driver);
  });

  test('call then push share the service', () async {
    await arbiter.need(ServiceOwner.push, _push);
    await arbiter.need(ServiceOwner.call, _call);
    await arbiter.need(ServiceOwner.call, _call2);
    await arbiter.release(ServiceOwner.call);

    expect(driver.log, [
      'start remoteMessaging "Iris is connected" push persistent=true',
      'retype microphone+remoteMessaging',
      'update "Call with Iris" persistent=true',
      'update "Call with Iris" persistent=true',
      'retype remoteMessaging',
      'update "Iris is connected" persistent=true',
    ]);
    expect(driver.log, isNot(contains('stop')));
    expect(arbiter.shown, ServiceOwner.push);
    expect(driver.told.map((m) => m['holder']), ['push', 'call', 'push']);

    await arbiter.release(ServiceOwner.push);
    expect(driver.log.last, 'stop');
    expect(arbiter.running, isFalse);
  });

  test('a call alone starts and stops the service as before', () async {
    await arbiter.need(ServiceOwner.call, _call);
    await arbiter.release(ServiceOwner.call);
    expect(driver.log, [
      'start microphone "Call with Iris" call persistent=false',
      'stop',
    ]);
  });

  test(
    'push switched on during a call joins it, the call stays shown',
    () async {
      await arbiter.need(ServiceOwner.call, _call);
      await arbiter.need(ServiceOwner.push, _push);
      expect(driver.log.skip(1), [
        'retype microphone+remoteMessaging',
        'update "Call with Iris" persistent=true',
      ]);
      expect(arbiter.shown, ServiceOwner.call);

      // The call ends: push keeps the service.
      await arbiter.release(ServiceOwner.call);
      expect(driver.log.last, 'update "Iris is connected" persistent=true');
      expect(driver.log, isNot(contains('stop')));
    },
  );

  test('push switched off during a call leaves the call alone', () async {
    await arbiter.need(ServiceOwner.push, _push);
    await arbiter.need(ServiceOwner.call, _call);
    driver.log.clear();
    await arbiter.release(ServiceOwner.push);
    expect(driver.log, [
      'retype microphone',
      'update "Call with Iris" persistent=false',
    ]);
    expect(arbiter.running, isTrue);
  });

  test('push text changes only while push is shown', () async {
    await arbiter.need(ServiceOwner.push, _push);
    await arbiter.need(ServiceOwner.call, _call);
    driver.log.clear();
    const lost = ServiceNotice(title: "Iris can't reach your server", text: '');
    arbiter.remember(ServiceOwner.push, lost);
    expect(driver.log, isEmpty);
    await arbiter.release(ServiceOwner.call);
    expect(
      driver.log.last,
      'update "Iris can\'t reach your server" persistent=true',
    );
  });

  test('a refused retype is tried again when the app comes back', () async {
    await arbiter.need(ServiceOwner.push, _push);
    await arbiter.need(ServiceOwner.call, _call);
    driver.retypeWorks = false;
    await arbiter.release(ServiceOwner.call);
    expect(arbiter.types, {
      ServiceType.microphone,
      ServiceType.remoteMessaging,
    });

    driver
      ..retypeWorks = true
      ..log.clear();
    await arbiter.resumed();
    expect(driver.log, ['retype remoteMessaging']);
    expect(arbiter.types, {ServiceType.remoteMessaging});

    driver.log.clear();
    await arbiter.resumed();
    expect(driver.log, isEmpty);
  });

  test('a start that fails is tried again on the next need', () async {
    driver.startWorks = false;
    expect(await arbiter.need(ServiceOwner.push, _push), isFalse);
    expect(arbiter.running, isFalse);
    driver.startWorks = true;
    expect(await arbiter.need(ServiceOwner.push, _push), isTrue);
    expect(driver.log.where((l) => l.startsWith('start')), hasLength(2));
  });

  test('calls made together run in order', () async {
    await Future.wait([
      arbiter.need(ServiceOwner.push, _push),
      arbiter.need(ServiceOwner.call, _call),
      arbiter.release(ServiceOwner.call),
    ]);
    expect(driver.log.first, startsWith('start remoteMessaging'));
    expect(driver.log.last, 'update "Iris is connected" persistent=true');
  });

  test('releasing an owner that holds nothing does nothing', () async {
    await arbiter.release(ServiceOwner.call);
    expect(driver.log, isEmpty);
  });
}
