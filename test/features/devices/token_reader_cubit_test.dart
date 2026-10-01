import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';

const app = 'com.syldel.delivery';

void main() {
  late AppDatabase database;
  late FakeAdbService adb;
  late RecentPackagesRepository recent;

  setUp(() async {
    database = await AppDatabase.inMemory();
    adb = FakeAdbService();
    recent = RecentPackagesRepository(database: database);
  });

  tearDown(() => database.close());

  Future<TokenReaderCubit> opened({
    List<String> installed = const ['com.alpha', app],
  }) async {
    adb.packages[redmiSerial] = installed;
    final cubit = TokenReaderCubit(serviceFor: (_) => adb, recent: recent);
    addTearDown(cubit.close);
    await cubit.openDevice('/sdk/adb', redmiSerial);
    return cubit;
  }

  test(
    'lists the packages with the recently used ones first, and searches',
    () async {
      await recent.remember(redmiSerial, app);
      final cubit = await opened(installed: ['com.alpha', 'com.beta', app]);
      expect(cubit.state.packagesStatus, PackagesStatus.ready);
      expect(cubit.state.packages, [app, 'com.alpha', 'com.beta']);
      cubit.search('BET');
      expect(cubit.state.packages, ['com.beta']);
    },
  );

  test('a package list that adb cannot read shows why', () async {
    adb.packagesError = const AdbException(
      '`adb -s X shell pm list packages -3` failed: error: device offline',
    );
    final cubit = await opened();
    expect(cubit.state.packagesStatus, PackagesStatus.failed);
    expect(cubit.state.packagesError, contains('device offline'));
  });

  test(
    "a debug build: the tokens, the project's sender preselected, the app remembered",
    () async {
      adb.runAs[app] = [
        RunAsTokens([
          FoundToken(token: otherDeviceToken, senderId: '999000999000'),
          FoundToken(token: fakeDeviceToken, senderId: '123456789012'),
        ]),
      ];
      final cubit = await opened();
      await cubit.readToken(app, projectNumber: '123456789012');
      final read = cubit.state.read as TokenReadFound;
      expect(read.method, TokenReadMethod.runAs);
      expect(read.tokens, hasLength(2));
      expect(read.preselectedSenderId, '123456789012');
      expect(await recent.recent(redmiSerial), [app]);
      expect(cubit.state.packages.first, app);
    },
  );

  test('a release build: logcat after the user confirms', () async {
    adb.runAs[app] = [const RunAsReleaseBuild()];
    adb.logcat[app] = [
      const LogcatRestartingApp(),
      const LogcatWaitingForApp(),
      const LogcatWatching(4242),
      LogcatFound(fakeDeviceToken),
    ];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadReleaseBuild(app));
    expect(adb.calls.where((c) => c.startsWith('logcat')), isEmpty);

    final steps = <TokenRead>[];
    final subscription = cubit.stream.listen((state) => steps.add(state.read));
    await cubit.readTokenFromLogcat(app);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(
      steps.whereType<TokenReadWatchingLogcat>().map((step) => step.progress),
      contains(const LogcatWatching(4242)),
    );
    expect(
      cubit.state.read,
      TokenReadFound(
        app,
        tokens: [FoundToken(token: fakeDeviceToken)],
        method: TokenReadMethod.logcat,
      ),
    );
  });

  test('no token yet, then launch and retry', () async {
    adb.runAs[app] = [
      const RunAsNoTokenYet(),
      RunAsTokens([
        FoundToken(token: fakeDeviceToken, senderId: '123456789012'),
      ]),
    ];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadNoTokenYet(app));
    await cubit.launchApp(app);
    expect(adb.calls, contains('launch $redmiSerial $app'));
    await cubit.readToken(app);
    expect(cubit.state.read, isA<TokenReadFound>());
  });

  test('a package that is not installed', () async {
    adb.runAs['com.gone'] = [const RunAsNotInstalled()];
    final cubit = await opened();
    await cubit.readToken('com.gone');
    expect(cubit.state.read, const TokenReadNotInstalled('com.gone'));
  });

  test('a failed read shows the message', () async {
    const message =
        '`adb -s X exec-out run-as app cat …` failed: error: device offline';
    adb.runAs[app] = [const RunAsFailed(message)];
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, const TokenReadFailed(app, message));
    cubit.dismiss();
    expect(cubit.state.read, const TokenReadIdle());
  });

  test('logcat endings: no token, and an app that does not start', () async {
    adb.logcat['com.release'] = [
      const LogcatRestartingApp(),
      const LogcatNoToken(),
    ];
    adb.logcat['com.slow'] = [
      const LogcatRestartingApp(),
      const LogcatAppDidNotStart(),
    ];
    final cubit = await opened();
    await cubit.readTokenFromLogcat('com.release');
    expect(cubit.state.read, const TokenReadLogcatNoToken('com.release'));
    await cubit.readTokenFromLogcat('com.slow');
    expect(cubit.state.read, const TokenReadAppDidNotStart('com.slow'));
  });

  test('ignores a second read while one is running', () async {
    final gate = Completer<RunAsResult>();
    adb.runAsGate = gate;
    final cubit = await opened();
    final first = cubit.readToken(app);
    expect(cubit.state.isBusy, isTrue);
    await cubit.readToken('com.alpha');
    gate.complete(
      RunAsTokens([
        FoundToken(token: fakeDeviceToken, senderId: '123456789012'),
      ]),
    );
    await first;
    expect(adb.calls.where((c) => c.startsWith('run-as')), hasLength(1));
  });

  group('one read at a time', () {
    test('two same-turn logcat reads start one logcat', () async {
      adb.logcat[app] = [const LogcatRestartingApp(), const LogcatWatching(1)];
      final cubit = await opened();
      final first = cubit.readTokenFromLogcat(app);
      final second = cubit.readTokenFromLogcat('com.alpha');
      await second;
      await cubit.close();
      await first;
      expect(adb.calls.where((c) => c.startsWith('logcat')), hasLength(1));
    });

    test(
      'a same-turn logcat read and readToken runs only the logcat',
      () async {
        final controller = StreamController<LogcatProgress>();
        addTearDown(controller.close);
        adb.openLogcat[app] = controller;
        adb.runAs['b'] = [
          RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '1')]),
        ];
        final cubit = await opened();
        final logcat = cubit.readTokenFromLogcat(app);
        await cubit.readToken('b');
        await Future<void>.delayed(Duration.zero);
        expect(adb.calls.where((c) => c.startsWith('run-as')), isEmpty);
        expect(cubit.state.read, isA<TokenReadWatchingLogcat>());
        controller.add(const LogcatNoToken());
        await controller.close();
        await logcat;
        expect(cubit.state.read, const TokenReadLogcatNoToken(app));
      },
    );

    test('dismiss while watching logcat stays idle and completes', () async {
      final controller = StreamController<LogcatProgress>();
      addTearDown(controller.close);
      adb.openLogcat[app] = controller;
      final cubit = await opened();
      var completed = false;
      final pending = cubit
          .readTokenFromLogcat(app)
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      controller.add(const LogcatWatching(123));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.read, isA<TokenReadWatchingLogcat>());
      expect(completed, isFalse);

      cubit.dismiss();
      await pending;
      expect(cubit.state.read, const TokenReadIdle());
      expect(completed, isTrue);
      expect(controller.hasListener, isFalse);

      controller.add(LogcatFound(fakeDeviceToken));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.read, const TokenReadIdle());
    });

    test('a run-as result after dismiss does not come back', () async {
      final gate = Completer<RunAsResult>();
      adb.runAsGate = gate;
      final cubit = await opened();
      final read = cubit.readToken(app);
      cubit.dismiss();
      gate.complete(
        RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '1')]),
      );
      await read;
      expect(cubit.state.read, const TokenReadIdle());
    });

    test('a run-as result after A, B, A does not land', () async {
      final gate = Completer<RunAsResult>();
      adb.runAsGate = gate;
      final cubit = await opened();
      final read = cubit.readToken(app);
      await cubit.openDevice('/sdk/adb', 'other-serial');
      await cubit.openDevice('/sdk/adb', redmiSerial);
      gate.complete(
        RunAsTokens([FoundToken(token: fakeDeviceToken, senderId: '1')]),
      );
      await read;
      expect(cubit.state.read, const TokenReadIdle());
    });

    test('a logcat failure shows its message', () async {
      adb.logcat[app] = [const LogcatFailed('x')];
      final cubit = await opened();
      await cubit.readTokenFromLogcat(app);
      expect(cubit.state.read, const TokenReadFailed(app, 'x'));
    });

    test('a logcat that ends without a result finds no token', () async {
      adb.logcat[app] = [const LogcatWatching(1)];
      final cubit = await opened();
      await cubit.readTokenFromLogcat(app);
      expect(cubit.state.read, const TokenReadLogcatNoToken(app));
    });

    test('a launch failure lands, unless the device changed', () async {
      adb.launchError = const AdbException('launch failed');
      final cubit = await opened();
      await cubit.launchApp(app);
      expect(cubit.state.read, const TokenReadFailed(app, 'launch failed'));
      cubit.dismiss();
      final launch = cubit.launchApp(app);
      await cubit.openDevice('/sdk/adb', 'other-serial');
      await launch;
      expect(cubit.state.read, const TokenReadIdle());
    });
  });

  test('an unexpected error ends the read as a failure, not stuck', () async {
    adb.runAsError = StateError('x');
    final cubit = await opened();
    await cubit.readToken(app);
    expect(cubit.state.read, isA<TokenReadFailed>());
    expect(cubit.state.isBusy, isFalse);
  });

  test('an unexpected package list error is shown, not thrown', () async {
    adb.packagesError = StateError('x');
    final cubit = await opened();
    expect(cubit.state.packagesStatus, PackagesStatus.failed);
    expect(cubit.state.packagesError, isNotNull);
  });

  test('an unexpected launch error is a failure', () async {
    adb.launchError = StateError('x');
    final cubit = await opened();
    await cubit.launchApp(app);
    expect(cubit.state.read, isA<TokenReadFailed>());
  });
}
