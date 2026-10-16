import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/notifications/local_notifications.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  test('registers the channels in plain groups: two sound-bearing chat '
      'channels, a quiet one, and security alerts under Account, and removes the '
      'retired ones — silence is per post, not per channel', () async {
    final notifications = installFakeLocalNotifications();

    await LocalNotifications().initialize();

    final chatChannels = notifications.channels
        .where((c) => c['groupId'] == 'chats_group')
        .toList();
    expect(
      chatChannels.map((c) => c['id']),
      unorderedEquals([messagesChannelId, 'group_messages', 'quiet_messages']),
    );
    for (final channel in chatChannels.where(
      (c) => c['id'] != 'quiet_messages',
    )) {
      expect(channel['playSound'], isTrue, reason: '${channel['id']}');
      expect(channel['sound'], 'message_tone');
      expect(channel['soundSource'], 0);
      expect(channel['name'], isNot(contains('(sound)')));
    }
    expect(
      chatChannels.singleWhere((c) => c['id'] == messagesChannelId)['name'],
      'Chat messages',
    );
    expect(
      chatChannels.singleWhere((c) => c['id'] == 'group_messages')['name'],
      'Room messages',
    );
    final quiet = chatChannels.singleWhere((c) => c['id'] == 'quiet_messages');
    expect(quiet['name'], 'Quiet messages');
    expect(quiet['playSound'], isFalse);
    expect(quiet['importance'], Importance.low.value);
    final security = notifications.channels.singleWhere(
      (c) => c['id'] == 'security',
    );
    expect(security['name'], 'Security alerts');
    expect(security['groupId'], 'account_group');
    expect(
      notifications.deletedChannels,
      unorderedEquals([
        'messages',
        'messages_group',
        'messages_sound_v1',
        'messages_group_sound_v1',
      ]),
    );
  });

  test('on iOS it initializes without prompting: onboarding owns the '
      'notification ask', () async {
    final notifications = installFakeLocalNotifications(
      platform: TargetPlatform.iOS,
    );
    await LocalNotifications(capabilities: iosCapabilities).initialize();

    expect(
      notifications.initializeArguments,
      allOf(
        containsPair('requestAlertPermission', false),
        containsPair('requestSoundPermission', false),
        containsPair('requestBadgePermission', false),
      ),
    );
  });

  group('channel names follow a language change', () {
    final greek = lookupAppLocalizations(const Locale('el'));

    test(
      'android registers the channels again under the new language',
      () async {
        final notifications = installFakeLocalNotifications();
        final service = LocalNotifications(capabilities: androidCapabilities);
        await service.initialize();
        notifications.channels.clear();

        await service.refreshChannelNames(greek);

        final chat = notifications.channels.singleWhere(
          (c) => c['id'] == messagesChannelId,
        );
        expect(chat['name'], greek.notificationsChannelChatMessages);
      },
    );

    test('before the first setup there is nothing to refresh', () async {
      final notifications = installFakeLocalNotifications();
      final service = LocalNotifications(capabilities: androidCapabilities);

      await service.refreshChannelNames(greek);

      expect(notifications.channels, isEmpty);
    });

    test('on iOS no channel is touched', () async {
      final notifications = installFakeLocalNotifications(
        platform: TargetPlatform.iOS,
      );
      final service = LocalNotifications(capabilities: iosCapabilities);
      await service.initialize();

      await service.refreshChannelNames(greek);

      expect(notifications.channels, isEmpty);
    });
  });
}
