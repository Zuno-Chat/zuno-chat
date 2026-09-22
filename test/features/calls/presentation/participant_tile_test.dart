import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/features/calls/presentation/participant_tile.dart';

void main() {
  const id = VoipParticipantId(userId: '@bob:example.org', deviceId: 'B');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 240, height: 240, child: child)),
  );

  testWidgets('shows Encrypting while key state is mismatched', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(id: id, isLocal: false),
          renderer: null,
          encrypting: true,
        ),
      ),
    );
    expect(find.text('Encrypting…'), findsOneWidget);
  });

  testWidgets('labels a remote on a weak connection', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: false,
            encrypted: true,
            lowBandwidth: true,
          ),
          renderer: null,
        ),
      ),
    );
    expect(find.text('Weak connection'), findsOneWidget);
  });

  testWidgets('a healthy remote has no label', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: false,
            encrypted: true,
          ),
          renderer: null,
        ),
      ),
    );
    expect(find.text('Encrypting…'), findsNothing);
    expect(find.text('Weak connection'), findsNothing);
  });

  testWidgets('the local tile is never labelled weak', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: true,
            encrypted: true,
            lowBandwidth: true,
          ),
          renderer: null,
        ),
      ),
    );
    expect(find.text('Weak connection'), findsNothing);
  });

  testWidgets('the local tile shows Encrypting while unkeyed', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(id: id, isLocal: true),
          renderer: null,
          encrypting: true,
        ),
      ),
    );
    expect(find.text('Encrypting…'), findsOneWidget);
  });

  testWidgets('the tile label is exposed to semantics', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: false,
            encrypted: true,
            lowBandwidth: true,
          ),
          renderer: null,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Weak connection'), findsOneWidget);
  });

  group('self-view mirroring', () {
    bool mirrorOf(WidgetTester tester) =>
        tester.widget<RTCVideoView>(find.byType(RTCVideoView)).mirror;

    testWidgets('the front camera preview is mirrored', (tester) async {
      await tester.pumpWidget(
        wrap(
          ParticipantTile(
            participant: const CallEngineParticipant(
              id: id,
              isLocal: true,
              videoEnabled: true,
              frontCamera: true,
            ),
            renderer: RTCVideoRenderer(),
          ),
        ),
      );
      expect(mirrorOf(tester), isTrue);
    });

    testWidgets('the rear camera preview is not mirrored', (tester) async {
      await tester.pumpWidget(
        wrap(
          ParticipantTile(
            participant: const CallEngineParticipant(
              id: id,
              isLocal: true,
              videoEnabled: true,
              frontCamera: false,
            ),
            renderer: RTCVideoRenderer(),
          ),
        ),
      );
      expect(mirrorOf(tester), isFalse);
    });

    Widget localTile(RTCVideoRenderer renderer, {required bool frontCamera}) =>
        wrap(
          ParticipantTile(
            participant: CallEngineParticipant(
              id: id,
              isLocal: true,
              videoEnabled: true,
              frontCamera: frontCamera,
            ),
            renderer: renderer,
          ),
        );

    testWidgets(
      'a camera switch hides the preview until the new camera draws',
      (tester) async {
        final renderer = RTCVideoRenderer();
        await tester.pumpWidget(localTile(renderer, frontCamera: true));
        await tester.pumpWidget(localTile(renderer, frontCamera: false));
        expect(find.byType(RTCVideoView), findsNothing);
        expect(find.byIcon(Icons.person_outline), findsNothing);

        renderer.value = renderer.value.copyWith(rotation: 90);
        await tester.pump();
        expect(find.byType(RTCVideoView), findsNothing);

        await tester.pump(const Duration(milliseconds: 100));
        expect(mirrorOf(tester), isFalse);
      },
    );

    testWidgets('a camera switch reveals the preview after a short wait', (
      tester,
    ) async {
      final renderer = RTCVideoRenderer();
      await tester.pumpWidget(localTile(renderer, frontCamera: true));
      await tester.pumpWidget(localTile(renderer, frontCamera: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RTCVideoView), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(mirrorOf(tester), isFalse);
    });

    testWidgets('a remote video is never mirrored', (tester) async {
      await tester.pumpWidget(
        wrap(
          ParticipantTile(
            participant: const CallEngineParticipant(
              id: id,
              isLocal: false,
              videoEnabled: true,
            ),
            renderer: RTCVideoRenderer(),
          ),
        ),
      );
      expect(mirrorOf(tester), isFalse);
    });
  });

  testWidgets('a named tile shows the name, with a crossed mic when muted', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: false,
            encrypted: true,
            audioMuted: true,
          ),
          renderer: null,
          name: 'Bob',
        ),
      ),
    );

    expect(find.text('Bob'), findsOneWidget);
    expect(find.bySemanticsLabel('Bob is muted'), findsOneWidget);
    final tile = tester.getRect(find.byType(ParticipantTile));
    final label = tester.getRect(find.text('Bob'));
    expect(label.left - tile.left, lessThan(40));
    expect(tile.bottom - label.bottom, lessThan(24));
  });

  testWidgets('a long name leaves room for the status badge', (tester) async {
    await tester.pumpWidget(
      wrap(
        ParticipantTile(
          participant: const CallEngineParticipant(id: id, isLocal: false),
          renderer: null,
          name: 'Bartholomew Maximilian ' * 3,
          encrypting: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Encrypting…'), findsOneWidget);
    final tile = tester.getRect(find.byType(ParticipantTile));
    final status = tester.getRect(find.text('Encrypting…'));
    final name = tester.getRect(find.textContaining('Bartholomew'));
    expect(status.top - tile.top, lessThan(24));
    expect(status.bottom, lessThan(name.top));
  });

  testWidgets('a tile whose status is shown elsewhere stays clean', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(
            id: id,
            isLocal: false,
            audioMuted: true,
            lowBandwidth: true,
          ),
          renderer: null,
          encrypting: true,
          showStatus: false,
          showMuted: false,
          borderRadius: 0,
        ),
      ),
    );

    expect(find.text('Encrypting…'), findsNothing);
    expect(find.text('Weak connection'), findsNothing);
    expect(find.byIcon(Icons.mic_off_outlined), findsNothing);
    expect(find.byType(ClipRRect), findsNothing);
  });

  testWidgets('tiles are rounded like the rest of the app by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ParticipantTile(
          participant: CallEngineParticipant(id: id, isLocal: true),
          renderer: null,
        ),
      ),
    );

    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      BorderRadius.circular(16),
    );
  });
}
