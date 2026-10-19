import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/models/call_failure.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  test('every failure reads as its English sentence', () {
    String of(CallFailure failure) => failure.message(englishLocalizations);

    expect(of(const CallConnectionLost()), 'Connection lost');
    expect(of(const CallDidNotConnect()), 'Call did not connect');
    expect(
      of(const CallMicrophoneUnavailable()),
      'Allow Zuno to use the microphone, then call back.',
    );
    expect(
      of(const CallNoPermissionToStart()),
      'You do not have permission to start calls in this room',
    );
    expect(
      of(const CallFull(6)),
      'This call is full. Up to 6 people can join a call.',
    );
    expect(
      of(const CallOnAnotherDevice()),
      'You are in this call on another device. Hang up there to join here.',
    );
  });

  test('a full call names the limit the server set', () {
    expect(
      const CallFull(8).message(englishLocalizations),
      'This call is full. Up to 8 people can join a call.',
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
