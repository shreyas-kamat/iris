/// Android allows Iris one foreground service, and two things want it: push holds a connection open for days, a voice
/// call needs the microphone for minutes. The arbiter owns the service and decides what it shows.
///
/// - The service runs while anyone needs it, and stops only when nobody does.
/// - Its type is the union of what its owners need: `remoteMessaging` for push, `microphone` for a call.
/// - While a call runs its notification (and buttons) is shown; push's comes back when the call ends.
/// - With push on, the service outlives the app's task (swiped away) and comes back after a reboot; a call alone stops
///   with the task, as it always has.
///
/// Changing the type means restarting the service (the plugin fixes it at start). The notification stays up and the
/// service is never stopped, but the service's isolate starts again, so push reconnects from its cursor. A restart can
/// be refused while the app is in the background (Android 12+); a type that could not be dropped is tried again when
/// the app is next in the foreground (`resumed`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/logging.dart';

enum ServiceOwner { push, call }

enum ServiceType { microphone, remoteMessaging }

@immutable
final class ServiceButton {
  const ServiceButton(this.id, this.text);

  final String id;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ServiceButton && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// What the service's notification says.
@immutable
final class ServiceNotice {
  const ServiceNotice({
    required this.title,
    required this.text,
    this.buttons = const [],
  });

  final String title;
  final String text;
  final List<ServiceButton> buttons;
}

/// The plugin underneath, behind an interface so the arbiter's rules can be tested without a phone.
abstract interface class ForegroundDriver {
  /// Starts the service. [channel] picks the notification channel, fixed for the service's life. [persistent]: keep
  /// running when the app's task is removed, and start again after a reboot.
  Future<bool> start({
    required Set<ServiceType> types,
    required ServiceNotice notice,
    required ServiceOwner channel,
    required bool persistent,
  });

  Future<void> update(ServiceNotice notice, {required bool persistent});

  /// Restarts the running service with [types]. False when Android refused.
  Future<bool> retype(Set<ServiceType> types);

  Future<void> stop();

  /// Sends [message] to the service's isolate.
  void tell(Map<String, Object?> message);
}

final class ForegroundArbiter {
  ForegroundArbiter(this._driver);

  static const _log = IrisLog('service');

  final ForegroundDriver _driver;
  final _notices = <ServiceOwner, ServiceNotice>{};
  final _holding = <ServiceOwner>{};

  bool _running = false;
  Set<ServiceType> _types = const {};
  ServiceOwner? _shown;

  /// Calls run one at a time, in order: a call that starts while push is starting must not race it.
  Future<void> _queue = Future.value();

  bool get running => _running;
  Set<ServiceType> get types => _types;

  /// Whose notification is up.
  ServiceOwner? get shown => _shown;

  /// [owner] needs the service, showing [notice] while it is the one shown. True once the service runs.
  Future<bool> need(ServiceOwner owner, ServiceNotice notice) => _serial(() {
    _notices[owner] = notice;
    _holding.add(owner);
    return _apply();
  });

  /// [owner] no longer needs the service.
  Future<void> release(ServiceOwner owner) => _serial(() async {
    if (!_holding.remove(owner)) return;
    _notices.remove(owner);
    await _apply();
  });

  /// Keeps [notice] for [owner] without showing it. Push's service isolate writes its own connection text; the
  /// arbiter only needs the latest for when a call hands the notification back.
  void remember(ServiceOwner owner, ServiceNotice notice) {
    if (_holding.contains(owner)) _notices[owner] = notice;
  }

  /// The app is in the foreground again: a type change Android refused earlier is tried again.
  Future<void> resumed() => _serial(() async {
    if (!_running) return;
    final wanted = _wantedTypes();
    if (setEquals(wanted, _types)) return;
    if (await _driver.retype(wanted)) _types = wanted;
  });

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Set<ServiceType> _wantedTypes() => {
    if (_holding.contains(ServiceOwner.call)) ServiceType.microphone,
    if (_holding.contains(ServiceOwner.push)) ServiceType.remoteMessaging,
  };

  bool get _persistent => _holding.contains(ServiceOwner.push);

  ServiceOwner? get _front => _holding.contains(ServiceOwner.call)
      ? ServiceOwner.call
      : (_holding.contains(ServiceOwner.push) ? ServiceOwner.push : null);

  Future<bool> _apply() async {
    final front = _front;
    if (front == null) {
      if (_running) {
        await _driver.stop();
        _running = false;
        _types = const {};
        _shown = null;
      }
      return false;
    }
    final notice = _notices[front]!;
    final wanted = _wantedTypes();
    if (!_running) {
      _running = await _driver.start(
        types: wanted,
        notice: notice,
        channel: front,
        persistent: _persistent,
      );
      if (!_running) {
        _log.warn('service did not start', data: front.name);
        return false;
      }
      _types = wanted;
    } else {
      if (!setEquals(wanted, _types)) {
        if (await _driver.retype(wanted)) {
          _types = wanted;
        } else {
          _log.warn('service type change refused; trying again later');
        }
      }
      await _driver.update(notice, persistent: _persistent);
    }
    if (_shown != front) {
      _shown = front;
      _driver.tell({'holder': front.name});
    }
    return true;
  }
}
