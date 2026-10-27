import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/forward_icon.dart';

void main() {
  testWidgets('the forward arrow is the reply arrow mirrored', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: ForwardIcon(size: 14, color: Colors.red)),
      ),
    );

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.reply_outlined);
    expect((icon.size, icon.color), (14.0, Colors.red));
    final mirror = tester.widget<Transform>(
      find.ancestor(of: find.byType(Icon), matching: find.byType(Transform)),
    );
    expect(mirror.transform.storage[0], -1);
  });
}
