import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/core/errors/connection_error.dart';

void main() {
  test('a failed request to an unreachable host is a connection error', () {
    expect(
      isConnectionError(
        http.ClientException(
          'Failed host lookup: example.org',
          Uri.parse('https://example.org'),
        ),
      ),
      isTrue,
    );
    expect(isConnectionError(const SocketException('offline')), isTrue);
    expect(isConnectionError(TimeoutException('slow')), isTrue);
    expect(isConnectionError(const TlsException('handshake')), isTrue);
  });

  test('an answer from the server is not a connection error', () {
    expect(
      isConnectionError(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'You are not invited to this room.',
        }),
      ),
      isFalse,
    );
  });

  test('a connection failure reads as what failed and what to do', () {
    expect(
      failureMessage(
        http.ClientException('Failed host lookup'),
        failed: 'Could not leave the room.',
      ),
      'Could not leave the room. Check your connection and try again.',
    );
  });

  test('any other failure keeps its own message', () {
    expect(
      failureMessage(
        StateError('bad state'),
        failed: 'Could not leave the room.',
      ),
      'Bad state: bad state',
    );
  });

  test('a programming error is not a connection error', () {
    expect(isConnectionError(StateError('bad state')), isFalse);
    expect(isConnectionError('Tried to request history'), isFalse);
  });
}
