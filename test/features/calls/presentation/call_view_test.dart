import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/calls/presentation/call_controls.dart';
import 'package:zuno/features/calls/presentation/call_stage.dart';
import 'package:zuno/features/calls/presentation/call_status_line.dart';
import 'package:zuno/features/calls/presentation/call_status_widgets.dart';
import 'package:zuno/features/calls/presentation/call_view.dart';
import 'package:zuno/features/calls/presentation/participant_tile.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/layout_matrix.dart';

void main() {
  late Room room;
  late List<String> pressed;

  setUp(() {
    final client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        senderId: '@me:example.org',
        stateKey: '',
        content: {'name': 'Weekend hike'},
      ),
    );
    pressed = [];
  });

  CallViewParticipant person(
    String name, {
    bool local = false,
    bool encrypted = true,
    bool encrypting = false,
    bool muted = false,
    bool weak = false,
    bool camera = false,
  }) {
    final userId = '@${name.toLowerCase()}:example.org';
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        senderId: userId,
        stateKey: userId,
        content: {'membership': 'join', 'displayname': name},
      ),
    );
    return CallViewParticipant(
      participant: CallEngineParticipant(
        id: VoipParticipantId(userId: userId, deviceId: 'D'),
        isLocal: local,
        encrypted: encrypted,
        audioMuted: muted,
        lowBandwidth: weak,
        videoEnabled: camera,
      ),
      renderer: null,
      user: local ? null : room.unsafeGetUserFromMemoryOrFallback(userId),
      encrypting: encrypting,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    CallKind kind = CallKind.voice,
    bool connecting = false,
    bool calling = false,
    bool withLocal = true,
    bool localCamera = false,
    List<CallViewParticipant> remote = const [],
    bool reconnecting = false,
    CallQuality quality = CallQuality.good,
    Size size = const Size(360, 640),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoDarkTheme,
        home: CallView(
          room: room,
          kind: kind,
          connecting: connecting,
          calling: calling,
          local: withLocal
              ? person('Me', local: true, camera: localCamera)
              : null,
          remote: remote,
          talkingSince: remote.isEmpty ? null : DateTime(2026, 9, 20),
          reconnecting: reconnecting,
          quality: quality,
          speakerOn: false,
          onToggleMute: () => pressed.add('mute'),
          onToggleCamera: () => pressed.add('camera'),
          onSwitchCamera: () => pressed.add('flip'),
          onToggleSpeaker: () => pressed.add('speaker'),
          onHangUp: () => pressed.add('end'),
        ),
      ),
    );
    await tester.pump();
  }

  CallStatus shownStatus(WidgetTester tester) =>
      tester.widget<CallStatusLine>(find.byType(CallStatusLine)).status;

  group('before anyone has joined', () {
    testWidgets('the caller sees who is being called, and only End call '
        'works', (tester) async {
      await pump(tester, connecting: true, calling: true);

      expect(find.byType(VoiceCallStage), findsOneWidget);
      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.text('Calling…'), findsOneWidget);
      await tester.tap(find.byTooltip('Mute'), warnIfMissed: false);
      await tester.tap(find.byTooltip('End call'));
      expect(pressed, ['end']);
    });

    testWidgets('the person answering sees Connecting', (tester) async {
      await pump(tester, connecting: true);

      expect(shownStatus(tester), CallStatus.connecting);
    });

    testWidgets('a video call waits on the same screen, not an empty video', (
      tester,
    ) async {
      await pump(tester, kind: CallKind.video, connecting: true, calling: true);

      expect(find.byType(VoiceCallStage), findsOneWidget);
      expect(find.byType(VideoCallHeader), findsNothing);
      for (final tile in find.byType(ParticipantTile).evaluate()) {
        expect(tile.size, const Size(100, 140));
      }
    });

    testWidgets('people the engine already lists do not show while still '
        'connecting', (tester) async {
      await pump(tester, connecting: true, remote: [person('Ann')]);

      expect(shownStatus(tester), CallStatus.connecting);
      expect(find.text('Ann'), findsNothing);
    });

    testWidgets('connected with nobody there yet says it is waiting', (
      tester,
    ) async {
      await pump(tester);

      expect(shownStatus(tester), CallStatus.waiting);
    });
  });

  group('a voice call with one person', () {
    testWidgets('shows them, the lock and the clock once both sides are '
        'encrypted', (tester) async {
      await pump(tester, remote: [person('Ann')]);

      expect(find.text('Ann'), findsOneWidget);
      expect(shownStatus(tester), CallStatus.talking);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byType(CallTimer), findsOneWidget);
    });

    testWidgets('says Encrypting while either side still lacks the keys', (
      tester,
    ) async {
      await pump(tester, remote: [person('Ann', encrypting: true)]);
      expect(shownStatus(tester), CallStatus.encrypting);
      expect(find.byType(CallTimer), findsNothing);

      await tester.pump(const Duration(seconds: 8));
      expect(find.text(EncryptingLabel.hint), findsOneWidget);
    });

    testWidgets('the buttons sit under the stage, clear of the navigation '
        'bar', (tester) async {
      await pump(tester, remote: [person('Ann')]);

      final dock = tester.getRect(find.byType(CallControls));
      expect(dock.bottom, lessThanOrEqualTo(640 - 48));
      expect(
        dock.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(VoiceCallStage)).bottom,
        ),
      );
    });
  });

  group('a video call with one person', () {
    testWidgets('their picture fills the screen, under the system bars, with '
        'the header, your view and the buttons over it', (tester) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [person('Ann', muted: true, weak: true)],
      );

      final tiles = find.byType(ParticipantTile);
      expect(tiles, findsNWidgets(2));
      expect(tester.getRect(tiles.first), const Rect.fromLTWH(0, 0, 360, 640));
      expect(find.byType(VideoCallHeader), findsOneWidget);
      expect(find.bySemanticsLabel('Ann is muted'), findsOneWidget);
      expect(find.text('Weak connection'), findsOneWidget);

      final header = tester.getRect(find.byType(VideoCallHeader));
      final self = tester.getRect(tiles.last);
      final dock = tester.getRect(find.byType(CallControls));
      expect(header.top, greaterThanOrEqualTo(24));
      expect(header.right, lessThanOrEqualTo(self.left));
      expect(self.size, const Size(100, 140));
      expect(dock.bottom, lessThanOrEqualTo(640 - 48));
      expect(header.bottom, lessThan(dock.top));
    });

    testWidgets('the remote tile carries no badge of its own: the header '
        'says Encrypting', (tester) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [person('Ann', encrypting: true)],
      );

      expect(find.text('Encrypting…'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VideoCallHeader),
          matching: find.text('Encrypting…'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('your own missing keys also count as Encrypting', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: zunoDarkTheme,
          home: CallView(
            room: room,
            kind: CallKind.video,
            connecting: false,
            calling: false,
            local: person('Me', local: true, encrypting: true),
            remote: [person('Ann')],
            talkingSince: DateTime(2026, 9, 20),
            reconnecting: false,
            quality: CallQuality.good,
            speakerOn: true,
            onToggleMute: () {},
            onToggleCamera: () {},
            onSwitchCamera: () {},
            onToggleSpeaker: () {},
            onHangUp: () {},
          ),
        ),
      );

      expect(
        tester.widget<VideoCallHeader>(find.byType(VideoCallHeader)).status,
        CallStatus.encrypting,
      );
    });
  });

  group('a video call that is still ringing', () {
    testWidgets('shows your own camera view, so Switch camera has something '
        'to switch', (tester) async {
      await pump(
        tester,
        kind: CallKind.video,
        calling: true,
        localCamera: true,
      );

      expect(find.byType(VoiceCallStage), findsOneWidget);
      expect(find.text('Calling…'), findsOneWidget);
      final self = find.byType(ParticipantTile);
      expect(self, findsOneWidget);
      expect(tester.getSize(self), const Size(100, 140));
      expect(tester.getRect(self).right, closeTo(360 - 12, 0.5));
    });

    testWidgets('a voice call has no such view', (tester) async {
      await pump(tester, calling: true);

      expect(find.byType(ParticipantTile), findsNothing);
    });

    testWidgets('your view stays put when the other side joins', (
      tester,
    ) async {
      await pump(
        tester,
        kind: CallKind.video,
        calling: true,
        localCamera: true,
      );
      final before = tester.state(find.byType(ParticipantTile));

      await pump(
        tester,
        kind: CallKind.video,
        localCamera: true,
        remote: [person('Ann', camera: true)],
      );
      expect(tester.state(find.byType(ParticipantTile).last), same(before));
    });
  });

  group('the buttons stay where they are', () {
    testWidgets('a press on End call that started before a notice appeared '
        'still ends the call', (tester) async {
      for (final kind in CallKind.values) {
        pressed = [];
        await tester.pumpWidget(const SizedBox());
        await pump(tester, kind: kind, remote: [person('Ann')]);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byTooltip('End call')),
        );
        await pump(
          tester,
          kind: kind,
          remote: [person('Ann')],
          reconnecting: true,
        );
        await gesture.up();
        await tester.pump();

        expect(pressed, ['end'], reason: '$kind');
      }
    });

    testWidgets('the same buttons survive every change of layout', (
      tester,
    ) async {
      await pump(tester, remote: [person('Ann')]);
      final controls = tester.element(find.byType(CallControls));

      await pump(tester, remote: [person('Ann', camera: true)]);
      await pump(tester, kind: CallKind.video, remote: [person('Ann')]);
      await pump(
        tester,
        kind: CallKind.video,
        remote: [person('Ann'), person('Ben')],
        quality: CallQuality.poor,
      );

      expect(tester.element(find.byType(CallControls)), same(controls));
    });
  });

  group('the Encrypting advice', () {
    testWidgets('keeps counting when a weak-connection notice appears', (
      tester,
    ) async {
      final ann = person('Ann', encrypting: true);
      await pump(tester, kind: CallKind.video, remote: [ann]);
      await tester.pump(const Duration(seconds: 6));

      await pump(
        tester,
        kind: CallKind.video,
        remote: [ann],
        quality: CallQuality.poor,
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.text(EncryptingLabel.hint), findsOneWidget);
    });

    testWidgets('a view with no record of you never claims the lock', (
      tester,
    ) async {
      await pump(tester, withLocal: false, remote: [person('Ann')]);

      expect(shownStatus(tester), CallStatus.encrypting);
      expect(find.bySemanticsLabel('Encrypted'), findsNothing);
    });
  });

  group('when only the other side has a camera on', () {
    testWidgets('a voice call still shows their picture full screen, without '
        'a view of your own', (tester) async {
      await pump(tester, remote: [person('Ann', camera: true)]);

      expect(find.byType(VoiceCallStage), findsNothing);
      expect(find.byType(VideoCallHeader), findsOneWidget);
      expect(find.byType(ParticipantTile), findsOneWidget);
      expect(
        tester.getRect(find.byType(ParticipantTile)),
        const Rect.fromLTWH(0, 0, 360, 640),
      );
    });
  });

  group('a group call', () {
    testWidgets('puts everyone in the grid, you last, each tile named, and '
        'the buttons under it', (tester) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [
          person('Ann'),
          person('Ben', muted: true),
          person('Cat', encrypting: true),
        ],
      );

      expect(find.byType(CallGrid), findsOneWidget);
      final names = tester
          .widgetList<ParticipantTile>(find.byType(ParticipantTile))
          .map((tile) => tile.name)
          .toList();
      expect(names, ['Ann', 'Ben', 'Cat', 'You']);
      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.byType(CallTimer), findsOneWidget);
      expect(find.bySemanticsLabel('Ben is muted'), findsOneWidget);
      expect(find.text('Encrypting…'), findsOneWidget);

      final grid = tester.getRect(find.byType(CallGrid));
      final dock = tester.getRect(find.byType(CallControls));
      expect(dock.top, greaterThanOrEqualTo(grid.bottom));
      expect(dock.bottom, lessThanOrEqualTo(640 - 48));
    });

    testWidgets('six people and five buttons fit a small phone', (
      tester,
    ) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [
          for (final n in ['Ann', 'Ben', 'Cat', 'Dan', 'Eve']) person(n),
        ],
        localCamera: true,
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ParticipantTile), findsNWidgets(6));
      expect(find.byTooltip('Switch camera'), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('End call')).width,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('trouble on the line', () {
    testWidgets('reconnecting covers the stage and says so', (tester) async {
      await pump(tester, remote: [person('Ann')], reconnecting: true);

      expect(find.byType(ReconnectingNotice), findsOneWidget);
      expect(find.byType(ConnectionQualityPill), findsNothing);
    });

    for (final kind in CallKind.values) {
      testWidgets('End call still works while reconnecting, $kind', (
        tester,
      ) async {
        await pump(
          tester,
          kind: kind,
          remote: [person('Ann')],
          reconnecting: true,
        );

        await tester.tap(find.byTooltip('End call'));
        expect(pressed, ['end']);
      });
    }

    testWidgets('in a group the weak-connection notice covers no name', (
      tester,
    ) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [person('Ann'), person('Ben')],
        quality: CallQuality.poor,
      );

      final pill = tester.getRect(find.byType(ConnectionQualityPill));
      for (final name in ['Ann', 'Ben', 'You']) {
        expect(
          pill.overlaps(tester.getRect(find.text(name))),
          isFalse,
          reason: name,
        );
      }
      expect(
        pill.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(CallGrid)).bottom),
      );
    });

    testWidgets('a weak connection shows above the buttons, not while '
        'connecting', (tester) async {
      await pump(
        tester,
        kind: CallKind.video,
        remote: [person('Ann')],
        quality: CallQuality.poor,
      );
      final pill = tester.getRect(find.byType(ConnectionQualityPill));
      expect(
        pill.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(CallControls)).top),
      );

      await pump(tester, connecting: true, quality: CallQuality.poor);
      expect(find.text('Poor connection, video reduced'), findsNothing);
    });
  });

  group('on any phone, font size, orientation and direction', () {
    CallView view({required CallKind kind, required List<String> others}) =>
        CallView(
          room: room,
          kind: kind,
          connecting: false,
          calling: false,
          local: person('Me', local: true, muted: true),
          remote: [
            for (final name in others)
              person(name, encrypting: name == 'Ann', muted: true, weak: true),
          ],
          talkingSince: DateTime(2026, 9, 20),
          reconnecting: false,
          quality: CallQuality.poor,
          speakerOn: true,
          onToggleMute: () {},
          onToggleCamera: () {},
          onSwitchCamera: () {},
          onToggleSpeaker: () {},
          onHangUp: () {},
        );

    Future<void> endCallReachable(WidgetTester tester, String name) async {
      final end = tester.getRect(find.byTooltip('End call'));
      final screen = tester.view.physicalSize;
      final stages = find.byType(VoiceCallStage);
      if (stages.evaluate().isNotEmpty) {
        final stage = tester.getRect(stages);
        final status = tester.getRect(find.byType(CallStatusLine));
        expect(status.top, greaterThanOrEqualTo(stage.top), reason: name);
        expect(status.bottom, lessThanOrEqualTo(stage.bottom), reason: name);
      }
      expect(end.left, greaterThanOrEqualTo(0), reason: name);
      expect(end.right, lessThanOrEqualTo(screen.width), reason: name);
      expect(end.bottom, lessThanOrEqualTo(screen.height), reason: name);
    }

    testWidgets('a voice call holds, End call always on screen', (
      tester,
    ) async {
      await expectSurvivesLayoutMatrix(
        tester,
        () => view(kind: CallKind.voice, others: ['Ann']),
        theme: zunoDarkTheme,
        afterEach: (name) => endCallReachable(tester, name),
      );
    });

    testWidgets('a video call holds, End call always on screen', (
      tester,
    ) async {
      await expectSurvivesLayoutMatrix(
        tester,
        () => view(kind: CallKind.video, others: ['Ann']),
        theme: zunoDarkTheme,
        afterEach: (name) => endCallReachable(tester, name),
      );
    });

    testWidgets('a full group call holds, End call always on screen', (
      tester,
    ) async {
      await expectSurvivesLayoutMatrix(
        tester,
        () => view(
          kind: CallKind.video,
          others: ['Ann', 'Ben', 'Cat', 'Dan', 'Eve'],
        ),
        theme: zunoDarkTheme,
        afterEach: (name) => endCallReachable(tester, name),
      );
    });
  });
}
