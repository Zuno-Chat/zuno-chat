import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_failure.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  test('every failure reads as its English sentence', () {
    String of(CallFailure failure) => failure.message(englishLocalizations);

    expect(of(CallFailure.connectionLost), 'Connection lost');
    expect(of(CallFailure.didNotConnect), 'Call did not connect');
    expect(
      of(CallFailure.microphoneUnavailable),
      'Allow Zuno to use the microphone, then call back.',
    );
    expect(
      of(CallFailure.noPermissionToStart),
      'You do not have permission to start calls in this room',
    );
    expect(
      of(CallFailure.callFull),
      'This call is full. Up to 6 people can join a call.',
    );
    expect(
      of(CallFailure.onAnotherDevice),
      'You are in this call on another device. Hang up there to join here.',
    );
  });

  test('the full-call sentence agrees with the count', () {
    expect(
      englishLocalizations.callsFailureCallFull(1),
      'This call is full. Up to 1 person can join a call.',
    );
    expect(
      englishLocalizations.callsFailureCallFull(6),
      'This call is full. Up to 6 people can join a call.',
    );
    expect(
      englishLocalizations.callsFailureCallFull(1200),
      'This call is full. Up to 1,200 people can join a call.',
    );
  });
}
