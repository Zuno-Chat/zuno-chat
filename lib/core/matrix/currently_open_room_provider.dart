import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/chat_route.dart';

final openChatObserverProvider = Provider<OpenChatObserver>((ref) {
  final observer = OpenChatObserver();
  ref.onDispose(observer.dispose);
  return observer;
});

final currentlyOpenRoomIdProvider =
    NotifierProvider<CurrentlyOpenRoomIdNotifier, String?>(
      CurrentlyOpenRoomIdNotifier.new,
    );

class CurrentlyOpenRoomIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    final observer = ref.watch(openChatObserverProvider);
    void follow() => state = observer.openRoomId;
    observer.addListener(follow);
    ref.onDispose(() => observer.removeListener(follow));
    return observer.openRoomId;
  }
}
