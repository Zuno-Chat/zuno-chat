import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/push_diagnostics_report.dart';
import 'package:zuno/core/push/pusher_info.dart';

import '../../helpers/platform_capabilities.dart';

void main() {
  final now = DateTime(2026, 10, 2, 12);
  final ios = capabilitiesLike(
    iosCapabilities,
    pushDiagnostics: true,
    voipRing: true,
    nseNotifications: true,
  );
  const pushkey = 'cHVzaGtleQ==';
  final gateway = Uri.parse('https://zuno.im/_matrix/push/v1/notify');

  PusherInfo pusher({
    String appId = 'im.zuno.chat.ios',
    String? url,
    String format = 'event_id_only',
  }) => PusherInfo(
    appId: appId,
    pushkey: pushkey,
    appDisplayName: 'Zuno',
    deviceDisplayName: 'iPhone',
    kind: 'http',
    lang: 'en',
    url: url ?? gateway.toString(),
    format: format,
  );

  PushDiagnosticsInputs inputs({
    PlatformCapabilities? capabilities,
    PushDiagnosticsSnapshot snapshot = const PushDiagnosticsSnapshot(
      environment: 'production',
    ),
    VoipDeviceStatus? voip = const VoipDeviceStatus(
      hasToken: true,
      callKit: true,
      environment: 'production',
      kid: 7,
    ),
    ServerHealth? health,
    ServerReach reach = ServerReach.reachable,
    List<PusherInfo>? pushers,
    bool pushersUnavailable = false,
    String? currentPushkey = pushkey,
  }) => PushDiagnosticsInputs(
    capabilities: capabilities ?? ios,
    now: now,
    appVersion: '1.2.0 (build 2)',
    snapshot: snapshot,
    voip: voip,
    health: health,
    reach: reach,
    pushers: pushersUnavailable ? null : pushers ?? [pusher()],
    currentPushkey: currentPushkey,
    expectedGateway: gateway,
  );

  DiagnosticSection section(PushDiagnosticsInputs from, String title) =>
      buildPushDiagnostics(from).firstWhere((s) => s.title == title);

  group('permission', () {
    test('Apple settings read in plain words, in a fixed order', () {
      final rows = section(
        inputs(
          snapshot: const PushDiagnosticsSnapshot(
            settings: {
              'alert': 'enabled',
              'authorization': 'authorized',
              'scheduledDelivery': 'enabled',
              'somethingNew': 'x',
            },
          ),
        ),
        'Permission',
      ).rows;
      expect(rows, const [
        DiagnosticRow('Notifications', 'Allowed', DiagnosticStatus.ok),
        DiagnosticRow('Alerts', 'On'),
        DiagnosticRow('Scheduled summary', 'On', DiagnosticStatus.warning),
        DiagnosticRow('somethingNew', 'x'),
      ]);
    });

    test('notifications not allowed, not asked, or alerts off are flagged', () {
      final rows = section(
        inputs(
          snapshot: const PushDiagnosticsSnapshot(
            settings: {'authorization': 'denied', 'alert': 'disabled'},
          ),
        ),
        'Permission',
      ).rows;
      expect(rows.first.status, DiagnosticStatus.problem);
      expect(rows.first.value, 'Not allowed');
      expect(rows.last.status, DiagnosticStatus.problem);
      expect(
        section(
          inputs(
            snapshot: const PushDiagnosticsSnapshot(
              settings: {'authorization': 'notDetermined'},
            ),
          ),
          'Permission',
        ).rows.single,
        const DiagnosticRow(
          'Notifications',
          'Not asked yet',
          DiagnosticStatus.warning,
        ),
      );
    });

    test('without the settings the section says they are not available', () {
      expect(
        section(inputs(), 'Permission').rows.single.value,
        'Not available on this device',
      );
    });
  });

  group('this device', () {
    test('a registered pusher at the expected address and format reads as '
        'correct', () {
      final device = section(inputs(), 'This device');
      expect(device.row('Environment')?.value, 'Production');
      expect(device.row('App ID')?.value, 'im.zuno.chat.ios');
      expect(device.row('Push key')?.status, DiagnosticStatus.ok);
      expect(device.row('Registration')?.value, 'Registered');
      expect(device.row('Gateway')?.value, 'Correct');
      expect(device.row('Format')?.value, 'Correct');
      expect(device.row('Zuno version')?.value, '1.2.0 (build 2)');
    });

    test('the same address in other letter case or with its default port is '
        'correct', () {
      final device = section(
        inputs(
          pushers: [pusher(url: 'https://ZUNO.im:443/_matrix/push/v1/notify')],
        ),
        'This device',
      );
      expect(device.row('Gateway')?.value, 'Correct');
    });

    test(
      'another address, another format or the wrong app ID is a problem',
      () {
        final device = section(
          inputs(
            pushers: [
              pusher(
                appId: 'im.zuno.chat.ios.dev',
                url: 'https://old.example/_matrix/push/v1/notify',
                format: 'full',
              ),
            ],
          ),
          'This device',
        );
        expect(
          device.row('Gateway'),
          const DiagnosticRow('Gateway', 'Different', DiagnosticStatus.problem),
        );
        expect(device.row('Format')?.status, DiagnosticStatus.problem);
        expect(
          device.row('App ID'),
          const DiagnosticRow(
            'App ID',
            'im.zuno.chat.ios.dev, expected im.zuno.chat.ios',
            DiagnosticStatus.problem,
          ),
        );
      },
    );

    test('no push key, no registration, or a list that could not be read', () {
      final missing = section(inputs(currentPushkey: null), 'This device');
      expect(missing.row('Push key')?.value, 'Missing');
      expect(missing.row('Registration')?.value, 'Not set up');
      expect(
        section(inputs(pushers: []), 'This device').row('Registration')?.value,
        'Not registered',
      );
      expect(
        section(
          inputs(pushersUnavailable: true),
          'This device',
        ).row('Registration'),
        const DiagnosticRow(
          'Registration',
          'Could not check',
          DiagnosticStatus.warning,
        ),
      );
    });
  });

  test('the call and extension sections follow their flags', () {
    final titles = buildPushDiagnostics(
      inputs(
        capabilities: capabilitiesLike(
          androidCapabilities,
          pushDiagnostics: true,
        ),
      ),
    ).map((s) => s.title);
    expect(titles, ['Permission', 'This device', 'Delivery']);
    expect(buildPushDiagnostics(inputs()).map((s) => s.title), [
      'Permission',
      'This device',
      'Calls',
      'Notification extension',
      'Delivery',
    ]);
  });

  group('calls', () {
    final sent = ServerHealth(
      voipRegistered: true,
      voipKid: 7,
      voipLastResult: 'sent',
      voipLastAt: now.subtract(const Duration(minutes: 10)),
    );

    test('the call key is current, out of date, not registered or '
        'unchecked', () {
      String key(ServerHealth? health) =>
          section(inputs(health: health), 'Calls').row('Call key')!.value;
      expect(
        key(const ServerHealth(voipRegistered: true, voipKid: 7)),
        'Current',
      );
      expect(
        key(const ServerHealth(voipRegistered: true, voipKid: 8)),
        'Out of date',
      );
      expect(key(const ServerHealth(voipRegistered: false)), 'Not registered');
      expect(key(null), 'Could not check');
    });

    test('a ring the server sent that never arrived is a problem', () {
      final missed = section(
        inputs(
          health: sent,
          snapshot: const PushDiagnosticsSnapshot(
            environment: 'production',
            ledger: [],
          ),
        ),
        'Calls',
      );
      expect(missed.row('Last ring sent')?.value, 'Sent 10 min ago');
      expect(missed.row('Last ring')?.status, DiagnosticStatus.problem);
      expect(missed.row('Last call activity')?.value, 'None yet');

      final arrived = section(
        inputs(
          health: sent,
          snapshot: PushDiagnosticsSnapshot(
            environment: 'production',
            ledger: [
              LedgerCall(
                state: 'ended',
                source: 'push',
                at: now.subtract(const Duration(minutes: 10)),
              ),
            ],
          ),
        ),
        'Calls',
      );
      expect(arrived.row('Last ring'), isNull);
      expect(arrived.row('Last call activity')?.value, '10 min ago');
    });

    test('a call that ran on after its ring is not reported as lost', () {
      final calls = section(
        inputs(
          health: sent,
          snapshot: PushDiagnosticsSnapshot(
            environment: 'production',
            ledger: [
              LedgerCall(
                state: 'ended',
                source: 'push',
                at: now.subtract(const Duration(minutes: 2)),
              ),
            ],
          ),
        ),
        'Calls',
      );
      expect(calls.row('Last ring'), isNull);
      expect(calls.row('Last call activity')?.value, '2 min ago');
    });

    test('a server that could not be asked leaves the last ring unknown', () {
      expect(
        section(inputs(), 'Calls').row('Last ring sent'),
        const DiagnosticRow(
          'Last ring sent',
          'Could not check',
          DiagnosticStatus.warning,
        ),
      );
      expect(
        section(
          inputs(health: const ServerHealth(voipRegistered: true)),
          'Calls',
        ).row('Last ring sent'),
        const DiagnosticRow('Last ring sent', 'None yet'),
      );
    });

    test('a call push key that could not be read is unknown, not missing', () {
      const server = ServerHealth(voipRegistered: true, voipKid: 7);
      final unread = section(inputs(voip: null, health: server), 'Calls');
      expect(
        unread.row('Call push key'),
        const DiagnosticRow(
          'Call push key',
          'Unknown',
          DiagnosticStatus.warning,
        ),
      );
      expect(
        unread.row('Call key'),
        const DiagnosticRow('Call key', 'Unknown', DiagnosticStatus.warning),
      );

      final none = section(
        inputs(
          voip: const VoipDeviceStatus(hasToken: false, callKit: true),
          health: server,
        ),
        'Calls',
      );
      expect(
        none.row('Call push key'),
        const DiagnosticRow(
          'Call push key',
          'Missing',
          DiagnosticStatus.problem,
        ),
      );
    });

    test('a ledger that was not read is unknown, not a lost ring', () {
      final unread = section(inputs(health: sent), 'Calls');
      expect(unread.row('Last ring'), isNull);
      expect(
        unread.row('Last call activity'),
        const DiagnosticRow(
          'Last call activity',
          'Unknown',
          DiagnosticStatus.warning,
        ),
      );
    });
  });

  group('notification extension', () {
    DiagnosticSection extension(PushDiagnosticsSnapshot snapshot) =>
        section(inputs(snapshot: snapshot), 'Notification extension');

    test('a run on another build asks for a restart', () {
      final other = extension(
        PushDiagnosticsSnapshot(
          extensionVersion: '1.2.0 (1)',
          extensionLastRun: now.subtract(const Duration(hours: 3)),
        ),
      );
      expect(other.row('Version')?.status, DiagnosticStatus.warning);
      expect(other.row('Version')?.value, contains('Restart this device'));
      expect(other.row('Last run')?.value, '3 h ago');
      expect(
        extension(const PushDiagnosticsSnapshot(extensionVersion: '1.2.0 (2)'))
            .row('Version')
            ?.status,
        DiagnosticStatus.ok,
      );
    });

    test('an extension that never ran says so', () {
      final never = extension(const PushDiagnosticsSnapshot());
      expect(
        never.row('Last run'),
        const DiagnosticRow('Last run', 'Never', DiagnosticStatus.warning),
      );
      expect(never.row('Version')?.value, 'Unknown');
      expect(never.row('Recent results')?.value, 'None yet');
    });
  });

  group('delivery', () {
    test('reach, last delivery, failures and extension access', () {
      final server = ServerHealth(
        voipRegistered: true,
        pushers: [
          PusherHealth(
            appId: 'im.zuno.chat.ios',
            lastSuccess: now.subtract(const Duration(minutes: 2)),
            failingSince: now.subtract(const Duration(minutes: 1)),
          ),
        ],
        credentialExpires: now.subtract(const Duration(days: 1)),
        lastFetch: now.subtract(const Duration(minutes: 30)),
        serverOffset: const Duration(minutes: 1),
      );
      final delivery = section(inputs(health: server), 'Delivery');
      expect(delivery.row('Reachable')?.value, 'Yes');
      expect(delivery.row('Last delivery')?.value, '3 min ago');
      expect(delivery.row('Failing since')?.status, DiagnosticStatus.problem);
      expect(delivery.row('Extension access')?.value, 'Expired');
      expect(delivery.row('Extension last checked in')?.value, '31 min ago');
    });

    test('a server that cannot be reached, is starting or has push turned '
        'off', () {
      expect(
        section(inputs(reach: ServerReach.unreachable), 'Delivery').rows,
        const [DiagnosticRow('Reachable', 'No', DiagnosticStatus.problem)],
      );
      expect(
        section(inputs(reach: ServerReach.starting), 'Delivery').rows.single,
        const DiagnosticRow('Reachable', 'Starting', DiagnosticStatus.warning),
      );
      expect(
        section(
          inputs(reach: ServerReach.turnedOff),
          'Delivery',
        ).rows.single.value,
        'Turned off',
      );
    });
  });

  test('device reports name what ended Zuno', () {
    final reports = section(
      inputs(
        snapshot: PushDiagnosticsSnapshot(
          metrics: [
            MetricReport(
              kind: 'exits',
              counts: const {'locked_file': 2},
              end: now.subtract(const Duration(days: 1)),
            ),
          ],
        ),
      ),
      'Device reports',
    );
    expect(
      reports.rows.single,
      const DiagnosticRow(
        'Background exits',
        'Held a file while suspended: 2 (1 day ago)',
        DiagnosticStatus.warning,
      ),
    );
  });

  test('ages read in minutes, hours and days', () {
    expect(
      ageLabel(now.subtract(const Duration(seconds: 20)), now),
      'Just now',
    );
    expect(ageLabel(now.add(const Duration(minutes: 5)), now), 'Just now');
    expect(
      ageLabel(now.subtract(const Duration(minutes: 59)), now),
      '59 min ago',
    );
    expect(ageLabel(now.subtract(const Duration(hours: 5)), now), '5 h ago');
    expect(ageLabel(now.subtract(const Duration(days: 1)), now), '1 day ago');
    expect(ageLabel(now.subtract(const Duration(days: 9)), now), '9 days ago');
  });

  test('builds compare by their version and build numbers', () {
    expect(sameBuild('1.2.0 (2)', '1.2.0 (build 2)'), isTrue);
    expect(sameBuild('1.2.0+2', '1.2.0 (build 2)'), isTrue);
    expect(sameBuild('1.2.0 (1)', '1.2.0 (build 2)'), isFalse);
    expect(sameBuild('1.3.0 (2)', '1.2.0 (build 2)'), isFalse);
  });

  test('the shared text carries no IDs, addresses or tokens', () {
    final text = redactedDiagnosticsText(
      buildPushDiagnostics(
        inputs(
          snapshot: const PushDiagnosticsSnapshot(
            extensionLog: [
              'shown for @alice:zuno.im in !abc:zuno.im '
                  r'event $ev1:zuno.im via https://zuno.im/x '
                  'token 2d2de6b6c6565ad95bf365845db19da9',
            ],
          ),
        ),
      ),
      now: now,
      appVersion: '1.2.0 (build 2)',
    );
    expect(text, startsWith('Zuno notification diagnostics'));
    expect(text, contains('Recent results'));
    for (final secret in [
      '@alice:zuno.im',
      '!abc:zuno.im',
      r'$ev1:zuno.im',
      'https://zuno.im',
      '2d2de6b6c6565ad95bf365845db19da9',
      pushkey,
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });
}
