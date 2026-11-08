import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/livekit/livekit_remotes.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_models.pb.dart';
import 'package:zuno/core/calls/media/call_connection.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/fake_webrtc.dart';

const _own = 'lk-me';

void _sendSubscriptions(LiveKitRemotes remotes) {
  final (:subscribe, :unsubscribe) = remotes.subscriptionChanges(
    remotes.wanted(),
  );
  remotes
    ..subscriptionsSent(subscribe, subscribe: true)
    ..subscriptionsSent(unsubscribe, subscribe: false);
}

TrackInfo _track(
  String sid, {
  TrackType type = TrackType.AUDIO,
  Encryption_Type encryption = Encryption_Type.GCM,
}) => TrackInfo(sid: sid, type: type, encryption: encryption);

ParticipantInfo _participant(
  String sid,
  String identity, {
  List<TrackInfo> tracks = const [],
  int version = 1,
  int joinedAtMs = 1,
  ParticipantInfo_State state = ParticipantInfo_State.ACTIVE,
}) => ParticipantInfo(
  sid: sid,
  identity: identity,
  tracks: tracks,
  version: version,
  joinedAtMs: Int64(joinedAtMs),
  state: state,
);

LiveKitArrival _arrival(
  String participantSid,
  String trackSid, {
  FakeReceiver? receiver,
}) => LiveKitArrival(
  participantSid: participantSid,
  trackSid: trackSid,
  receiver: receiver ?? FakeReceiver('r-$trackSid', null),
  stream: FakeMediaStream('$participantSid|$trackSid'),
);

const _both = {MediaKind.audio, MediaKind.video};

void main() {
  group('stream ids', () {
    test('a packed stream id names the participant and the track', () {
      expect(parseLiveKitStreamId('PA_ann|TR_a', 'ignored'), (
        participantSid: 'PA_ann',
        trackSid: 'TR_a',
      ));
    });

    test('a synced stream id takes the track sid from the track', () {
      expect(parseLiveKitStreamId('PA_ann|camera', 'TR_v'), (
        participantSid: 'PA_ann',
        trackSid: 'TR_v',
      ));
    });

    test('a stream id without a participant is not LiveKit media', () {
      expect(parseLiveKitStreamId('TR_a', 'TR_a'), isNull);
      expect(parseLiveKitStreamId('|TR_a', 'TR_a'), isNull);
    });
  });

  group('subscriptions', () {
    test('only GCM tracks of wanted kinds are subscribed', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [
              _track('TR_gcm'),
              _track('TR_plain', encryption: Encryption_Type.NONE),
              _track('TR_video', type: TrackType.VIDEO),
            ],
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', const {MediaKind.audio});

      final changes = remotes.subscriptionChanges(remotes.wanted());

      expect(changes.subscribe, ['TR_gcm']);
      expect(changes.unsubscribe, isEmpty);
    });

    test('sent subscriptions are not asked for again, and kinds no longer '
        'wanted are unsubscribed', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [
              _track('TR_a'),
              _track('TR_v', type: TrackType.VIDEO),
            ],
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both);
      _sendSubscriptions(remotes);

      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, isEmpty);

      remotes.setMember(ann, 'lk-ann', const {MediaKind.audio});

      expect(remotes.subscriptionChanges(remotes.wanted()).unsubscribe, [
        'TR_v',
      ]);
    });

    test('nothing is subscribed without a membership for the identity', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_eve', 'lk-eve', tracks: [_track('TR_e')]),
        ], ownIdentity: _own);

      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, isEmpty);
    });

    test('our own participant is never subscribed', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_me', _own, tracks: [_track('TR_mine')]),
        ], ownIdentity: _own)
        ..setMember(ann, _own, _both);

      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, isEmpty);
    });

    test('a participant that rejoins with a new sid swaps its tracks', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_old', 'lk-ann', tracks: [_track('TR_old')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both);
      _sendSubscriptions(remotes);

      remotes.updateParticipants([
        _participant(
          'PA_new',
          'lk-ann',
          tracks: [_track('TR_new')],
          joinedAtMs: 2,
        ),
      ], ownIdentity: _own);

      final changes = remotes.subscriptionChanges(remotes.wanted());
      expect(changes.subscribe, ['TR_new']);
      expect(changes.unsubscribe, ['TR_old']);
    });

    test('a member whose participant leaves or rejoins with a new sid has '
        'departed', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann'),
          _participant('PA_bob', 'lk-bob'),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..setMember(bob, 'lk-bob', _both);

      expect(
        remotes.updateParticipants([
          _participant('PA_ann', 'lk-ann', version: 2),
        ], ownIdentity: _own).departed,
        isEmpty,
      );
      expect(
        remotes.updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            state: ParticipantInfo_State.DISCONNECTED,
          ),
          _participant('PA_bob2', 'lk-bob', joinedAtMs: 2),
        ], ownIdentity: _own).departed,
        {ann, bob},
      );
    });

    test('a late update for the replaced sid changes nothing', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_new',
            'lk-ann',
            tracks: [_track('TR_new')],
            joinedAtMs: 2,
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..updateParticipants([
          _participant('PA_old', 'lk-ann', tracks: [_track('TR_old')]),
          _participant(
            'PA_old',
            'lk-ann',
            state: ParticipantInfo_State.DISCONNECTED,
            version: 2,
          ),
        ], ownIdentity: _own);

      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, [
        'TR_new',
      ]);
    });

    test('an older version of a participant is ignored', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [_track('TR_a')],
            version: 3,
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', version: 2),
        ], ownIdentity: _own);

      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, ['TR_a']);
    });

    test('a resync asks for every wanted track and unsubscribes what may '
        'still be subscribed', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [
              _track('TR_a'),
              _track('TR_v', type: TrackType.VIDEO),
              _track('TR_x'),
            ],
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both);
      _sendSubscriptions(remotes);
      remotes.updateParticipants([
        _participant(
          'PA_ann',
          'lk-ann',
          tracks: [
            _track('TR_a'),
            _track('TR_v', type: TrackType.VIDEO),
          ],
          version: 2,
        ),
      ], ownIdentity: _own);
      _sendSubscriptions(remotes);
      remotes.setMember(ann, 'lk-ann', const {MediaKind.audio});

      expect(remotes.resync(), ['TR_a']);

      final changes = remotes.subscriptionChanges(remotes.wanted());
      expect(changes.subscribe, isEmpty);
      expect(changes.unsubscribe, unorderedEquals(['TR_v', 'TR_x']));
    });

    test('a reset forgets what was subscribed, so all is asked again', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both);
      _sendSubscriptions(remotes);

      remotes
        ..resetSession()
        ..updateParticipants([
          _participant('PA_ann2', 'lk-ann', tracks: [_track('TR_a2')]),
        ], ownIdentity: _own);

      final changes = remotes.subscriptionChanges(remotes.wanted());
      expect(changes.subscribe, ['TR_a2']);
      expect(changes.unsubscribe, isEmpty);
    });
  });

  group('arrivals', () {
    test('an early track waits for its participant and membership, then '
        'attaches to that device', () {
      final remotes = LiveKitRemotes()..arrived(_arrival('PA_ann', 'TR_a'));

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);

      remotes.updateParticipants([
        _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
        _participant('PA_bob', 'lk-bob', tracks: [_track('TR_b')]),
      ], ownIdentity: _own);
      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);

      remotes
        ..setMember(bob, 'lk-bob', _both)
        ..setMember(ann, 'lk-ann', _both);

      final attach = remotes.attachments(remotes.wanted()).attach.single;
      expect(attach.slot, (id: ann, kind: MediaKind.audio));
      expect(attach.arrival.trackSid, 'TR_a');
      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('a track for an identity with no membership never attaches', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_eve', 'lk-eve', tracks: [_track('TR_e')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_eve', 'TR_e'));

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('a track under another participant sid never attaches', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_eve', 'TR_a'));

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('an unencrypted track never attaches, even when its kind is '
        'wanted', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [_track('TR_a', encryption: Encryption_Type.NONE)],
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_ann', 'TR_a'));

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('a kind no longer wanted detaches, and attaches again once '
        'wanted', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [_track('TR_v', type: TrackType.VIDEO)],
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_ann', 'TR_v'));
      expect(remotes.attachments(remotes.wanted()).attach, hasLength(1));

      remotes.setMember(ann, 'lk-ann', const {MediaKind.audio});
      expect(remotes.attachments(remotes.wanted()).detach, [
        (id: ann, kind: MediaKind.video),
      ]);

      remotes.setMember(ann, 'lk-ann', _both);
      expect(
        remotes.attachments(remotes.wanted()).attach.single.arrival.trackSid,
        'TR_v',
      );
    });

    test('a removed track detaches and is never attached again', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_ann', 'TR_a'));
      remotes.attachments(remotes.wanted());

      remotes.departed('TR_a');
      expect(remotes.attachments(remotes.wanted()).detach, [
        (id: ann, kind: MediaKind.audio),
      ]);
      remotes.setMember(ann, 'lk-ann', _both);

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('a receiver reused for another track drops the older arrival', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
          _participant('PA_bob', 'lk-bob', tracks: [_track('TR_b')]),
        ], ownIdentity: _own)
        ..arrived(
          _arrival('PA_ann', 'TR_a', receiver: FakeReceiver('reused', null)),
        )
        ..arrived(
          _arrival('PA_bob', 'TR_b', receiver: FakeReceiver('reused', null)),
        )
        ..setMember(ann, 'lk-ann', _both)
        ..setMember(bob, 'lk-bob', _both);

      final attach = remotes.attachments(remotes.wanted()).attach.single;
      expect(attach.slot, (id: bob, kind: MediaKind.audio));
    });

    test('a receiver reused for another track releases the slot it was '
        'attached to', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
          _participant('PA_bob', 'lk-bob', tracks: [_track('TR_b')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..setMember(bob, 'lk-bob', _both)
        ..arrived(
          _arrival('PA_ann', 'TR_a', receiver: FakeReceiver('reused', null)),
        );
      remotes.attachments(remotes.wanted());

      remotes.arrived(
        _arrival('PA_bob', 'TR_b', receiver: FakeReceiver('reused', null)),
      );
      final (:detach, :attach) = remotes.attachments(remotes.wanted());

      expect(detach, [(id: ann, kind: MediaKind.audio)]);
      expect(attach.single.slot, (id: bob, kind: MediaKind.audio));
    });

    test('a different receiver keeps the attached arrival', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
          _participant('PA_bob', 'lk-bob', tracks: [_track('TR_b')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..setMember(bob, 'lk-bob', _both)
        ..arrived(_arrival('PA_ann', 'TR_a'));
      remotes.attachments(remotes.wanted());

      remotes.arrived(_arrival('PA_bob', 'TR_b'));
      final (:detach, :attach) = remotes.attachments(remotes.wanted());

      expect(detach, isEmpty);
      expect(attach.single.slot, (id: bob, kind: MediaKind.audio));
    });

    test('a departed participant drops its waiting tracks', () {
      final remotes = LiveKitRemotes()
        ..arrived(_arrival('PA_ann', 'TR_a'))
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            state: ParticipantInfo_State.DISCONNECTED,
          ),
        ], ownIdentity: _own)
        ..updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [_track('TR_a')],
            version: 2,
          ),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both);

      expect(remotes.attachments(remotes.wanted()).attach, isEmpty);
    });

    test('a removed membership detaches its tracks', () {
      final remotes = LiveKitRemotes()
        ..updateParticipants([
          _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
        ], ownIdentity: _own)
        ..setMember(ann, 'lk-ann', _both)
        ..arrived(_arrival('PA_ann', 'TR_a'));
      remotes.attachments(remotes.wanted());

      remotes.removeMember(ann);

      expect(remotes.attachments(remotes.wanted()).detach, [
        (id: ann, kind: MediaKind.audio),
      ]);
      expect(remotes.subscriptionChanges(remotes.wanted()).subscribe, isEmpty);
    });
  });

  group('sending media', () {
    test('a member sends media once its participant has a published '
        'track', () {
      final remotes = LiveKitRemotes()..setMember(ann, 'lk-ann', _both);
      expect(remotes.sendingMedia(ann), isFalse);

      final changed = remotes.updateParticipants([
        _participant('PA_ann', 'lk-ann', tracks: [_track('TR_a')]),
      ], ownIdentity: _own).sendingChanged;

      expect(changed, isTrue);
      expect(remotes.sendingMedia(ann), isTrue);
      expect(
        remotes.updateParticipants([
          _participant(
            'PA_ann',
            'lk-ann',
            tracks: [_track('TR_a')],
            version: 2,
          ),
        ], ownIdentity: _own).sendingChanged,
        isFalse,
      );
    });

    test('the member for an identity is found for its ratings', () {
      final remotes = LiveKitRemotes()..setMember(ann, 'lk-ann', _both);

      expect(remotes.memberWith('lk-ann'), ann);
      expect(remotes.memberWith('lk-eve'), isNull);
    });
  });
}
