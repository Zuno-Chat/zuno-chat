import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/data/chat_timeline.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  test('tells its listeners when the timeline is replaced and when it '
      'changes', () async {
    final timeline = await (buildTestRoom(
      buildTestClient(database: TimelineCapableFakeDatabaseApi()),
    )..partial = false).getTimeline();
    addTearDown(timeline.cancelSubscriptions);
    final chat = ChatTimeline();
    addTearDown(chat.dispose);
    var told = 0;
    chat.addListener(() => told++);

    chat.value = timeline;
    expect(chat.value, same(timeline));
    expect(told, 1);

    chat.value = timeline;
    expect(told, 1);

    chat.changed();
    expect(told, 2);
  });
}
