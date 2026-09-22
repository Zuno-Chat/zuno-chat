import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/features/settings/presentation/session_info.dart';

void main() {
  group('mergeSessionInfo', () {
    test('current session sorts first regardless of activity time', () {
      final sessions = mergeSessionInfo(
        deviceKeys: [
          (deviceId: 'CURRENT', displayName: 'This device', verified: true),
          (deviceId: 'OLD', displayName: 'Old laptop', verified: false),
        ],
        devices: [
          (
            deviceId: 'CURRENT',
            displayName: 'This device',
            lastSeenTs: 1000,
            lastSeenIp: '10.0.0.1',
          ),
          (
            deviceId: 'OLD',
            displayName: 'Old laptop',
            lastSeenTs: 999999999,
            lastSeenIp: '10.0.0.2',
          ),
        ],
        currentDeviceId: 'CURRENT',
      );

      expect(sessions.map((s) => s.deviceId), ['CURRENT', 'OLD']);
      expect(sessions.first.isCurrent, isTrue);
    });

    test('other sessions sort by most recently active first', () {
      final sessions = mergeSessionInfo(
        deviceKeys: [],
        devices: [
          (deviceId: 'A', displayName: 'A', lastSeenTs: 100, lastSeenIp: null),
          (deviceId: 'B', displayName: 'B', lastSeenTs: 300, lastSeenIp: null),
          (deviceId: 'C', displayName: 'C', lastSeenTs: 200, lastSeenIp: null),
        ],
        currentDeviceId: null,
      );

      expect(sessions.map((s) => s.deviceId), ['B', 'C', 'A']);
    });

    test('a device missing lastActivity sorts after devices that have it', () {
      final sessions = mergeSessionInfo(
        deviceKeys: [],
        devices: [
          (
            deviceId: 'HAS_TIME',
            displayName: null,
            lastSeenTs: 100,
            lastSeenIp: null,
          ),
          (
            deviceId: 'NO_TIME',
            displayName: null,
            lastSeenTs: null,
            lastSeenIp: null,
          ),
        ],
        currentDeviceId: null,
      );

      expect(sessions.map((s) => s.deviceId), ['HAS_TIME', 'NO_TIME']);
    });

    test('devices API display name wins over device_keys display name', () {
      final sessions = mergeSessionInfo(
        deviceKeys: [
          (deviceId: 'X', displayName: 'From keys query', verified: true),
        ],
        devices: [
          (
            deviceId: 'X',
            displayName: 'From devices API',
            lastSeenTs: null,
            lastSeenIp: null,
          ),
        ],
        currentDeviceId: null,
      );

      expect(sessions.single.displayName, 'From devices API');
      expect(sessions.single.verified, isTrue);
    });

    test(
      'falls back to the device_keys display name when devices API has none',
      () {
        final sessions = mergeSessionInfo(
          deviceKeys: [
            (deviceId: 'X', displayName: 'From keys query', verified: false),
          ],
          devices: [
            (
              deviceId: 'X',
              displayName: null,
              lastSeenTs: null,
              lastSeenIp: null,
            ),
          ],
          currentDeviceId: null,
        );

        expect(sessions.single.displayName, 'From keys query');
      },
    );

    test(
      'a device present in only the devices API still gets a row, unverified',
      () {
        final sessions = mergeSessionInfo(
          deviceKeys: [],
          devices: [
            (
              deviceId: 'UNKNOWN_TO_KEYS_QUERY',
              displayName: 'Mystery',
              lastSeenTs: null,
              lastSeenIp: null,
            ),
          ],
          currentDeviceId: null,
        );

        expect(sessions.single.verified, isFalse);
        expect(sessions.single.displayName, 'Mystery');
      },
    );

    test('a device present in only the device_keys list still gets a row', () {
      final sessions = mergeSessionInfo(
        deviceKeys: [
          (deviceId: 'KEYS_ONLY', displayName: 'Keys only', verified: true),
        ],
        devices: [],
        currentDeviceId: null,
      );

      expect(sessions.single.deviceId, 'KEYS_ONLY');
      expect(sessions.single.verified, isTrue);
      expect(sessions.single.lastActivity, isNull);
    });
  });

  group('formatLastActivity', () {
    test('null time reads as Unknown', () {
      expect(formatLastActivity(null), 'Unknown');
    });

    test('formats a real time as a human-friendly date and 12-hour time', () {
      final time = DateTime(2026, 8, 31, 14, 32);
      expect(formatLastActivity(time), 'Aug 31, 2026 at 2:32 PM');
    });

    test('pads the minute but not the day/hour', () {
      final time = DateTime(2026, 1, 2, 3, 4);
      expect(formatLastActivity(time), 'Jan 2, 2026 at 3:04 AM');
    });

    test('midnight reads as 12 AM, not 0 AM', () {
      final time = DateTime(2026, 1, 1, 0, 0);
      expect(formatLastActivity(time), 'Jan 1, 2026 at 12:00 AM');
    });

    test('noon reads as 12 PM, not 0 PM', () {
      final time = DateTime(2026, 1, 1, 12, 0);
      expect(formatLastActivity(time), 'Jan 1, 2026 at 12:00 PM');
    });
  });

  group('sessionApproval', () {
    test('this phone is approved once it holds the identity keys', () {
      expect(
        sessionApproval(
          isCurrent: true,
          verified: true,
          thisDeviceHasIdentityKeys: true,
        ),
        SessionApproval.approved,
      );
    });

    test('this phone is not approved without them, whatever the SDK says', () {
      expect(
        sessionApproval(
          isCurrent: true,
          verified: true,
          thisDeviceHasIdentityKeys: false,
        ),
        SessionApproval.notApproved,
      );
    });

    test('this phone is never "can\'t check" — it is the one asking', () {
      expect(
        sessionApproval(
          isCurrent: true,
          verified: false,
          thisDeviceHasIdentityKeys: false,
        ),
        isNot(SessionApproval.unknown),
      );
    });

    test('another device is judged on its own signature chain', () {
      expect(
        sessionApproval(
          isCurrent: false,
          verified: true,
          thisDeviceHasIdentityKeys: true,
        ),
        SessionApproval.approved,
      );
      expect(
        sessionApproval(
          isCurrent: false,
          verified: false,
          thisDeviceHasIdentityKeys: true,
        ),
        SessionApproval.notApproved,
      );
    });

    test('another device cannot be judged from an unapproved phone', () {
      expect(
        sessionApproval(
          isCurrent: false,
          verified: false,
          thisDeviceHasIdentityKeys: false,
        ),
        SessionApproval.unknown,
      );
    });

    test('nothing is claimed while the account facts are still loading', () {
      expect(
        sessionApproval(
          isCurrent: true,
          verified: true,
          thisDeviceHasIdentityKeys: null,
        ),
        SessionApproval.unknown,
      );
      expect(
        sessionApproval(
          isCurrent: false,
          verified: true,
          thisDeviceHasIdentityKeys: null,
        ),
        SessionApproval.unknown,
      );
    });
  });
}
