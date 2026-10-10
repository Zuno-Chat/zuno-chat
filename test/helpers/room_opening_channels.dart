import 'fake_calls_channel.dart';
import 'fake_local_notifications.dart';
import 'native_method_calls.dart';

void installRoomOpeningChannels() {
  installFakeLocalNotifications();
  installFakeCallsChannel();
  silenceMethodChannels(const ['com.llfbandit.record/messages']);
}
