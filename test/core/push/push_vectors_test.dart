import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/push/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? value) =>
    (value! as List).cast<Map<String, Object?>>();

List<int> _range(int first, int last) => [
  for (var byte = first; byte <= last; byte++) byte,
];

int _uint32(List<int> bytes, int offset) =>
    ByteData.sublistView(Uint8List.fromList(bytes.sublist(offset, offset + 4)))
        .getUint32(0);

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String _uuidV5(String namespace, String name) {
  final compact = namespace.replaceAll('-', '');
  final namespaceBytes = [
    for (var i = 0; i < 32; i += 2)
      int.parse(compact.substring(i, i + 2), radix: 16),
  ];
  final hash = sha1
      .convert([...namespaceBytes, ...utf8.encode(name)])
      .bytes
      .sublist(0, 16);
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  final hex = _hex(hash).toUpperCase();
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20),
  ].join('-');
}

bool _stripped(int scalar) =>
    scalar <= 0x1f ||
    (scalar >= 0x7f && scalar <= 0x9f) ||
    scalar == 0x061c ||
    scalar == 0x200e ||
    scalar == 0x200f ||
    (scalar >= 0x202a && scalar <= 0x202e) ||
    (scalar >= 0x2066 && scalar <= 0x2069);

String _normalizedName(String name) {
  final kept = StringBuffer();
  var used = 0;
  for (final scalar in name.runes.where((scalar) => !_stripped(scalar))) {
    final size = utf8.encode(String.fromCharCode(scalar)).length;
    if (used + size > 64) break;
    used += size;
    kept.writeCharCode(scalar);
  }
  return kept.toString();
}

void main() {
  group('the VoIP blob vectors', () {
    final fixture = _fixture('voip_blob_v1.json');
    final vectors = _list(fixture['vectors']);
    final known = vectors.singleWhere((v) => v['name'] == 'known_answer');
    final knownBlob = base64Decode(known['blob']! as String);

    test('the known answer is the contract vector', () {
      expect(fixture['key'], 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=');
      expect(fixture['kid'], 16909060);
      expect(fixture['aad_prefix'], 'zuno-voip-v1');
      expect(known['x'], 1790000045);
      expect(base64Decode(known['nonce']! as String), _range(0xa0, 0xab));
      expect(
        known['plaintext'],
        '{"room":"!abc:zuno.im","call":"c1","caller":"@alice:zuno.im",'
        '"cname":"Alice","rname":"","kind":"video","ts":1790000000000,'
        '"rts":1789999999000}',
      );
      expect(knownBlob, hasLength(549));
      expect(
        sha256.convert(knownBlob).toString(),
        'aaf898f4941c4ff73dd0b30839264042535a098823be3a5ed024339fc58b6a80',
      );
    });

    test('every blob starts with its clear version, kid, expiry and '
        'nonce', () {
      for (final vector in vectors) {
        final blob = base64Decode(vector['blob']! as String);
        final padded = vector['padded_length']! as int;
        final name = '${vector['name']}';
        expect(blob[0], 0x01, reason: name);
        expect(_uint32(blob, 1), fixture['kid'], reason: name);
        expect(_uint32(blob, 5), vector['x'], reason: name);
        expect(
          blob.sublist(9, 21),
          base64Decode(vector['nonce']! as String),
          reason: name,
        );
        expect(blob, hasLength(1 + 4 + 4 + 12 + padded + 16), reason: name);
        expect(vector['blob_length'], blob.length, reason: name);
        expect(
          sha256.convert(blob).toString(),
          vector['blob_sha256'],
          reason: name,
        );
      }
    });

    test('the plaintext is compact JSON in the contract order, raw UTF-8, '
        'padded to 512 bytes, or 1024 past that', () {
      for (final vector in vectors) {
        final plaintext = vector['plaintext']! as String;
        final decoded = jsonDecode(plaintext) as Map<String, Object?>;
        expect(decoded.keys, [
          'room',
          'call',
          'caller',
          'cname',
          'rname',
          'kind',
          'ts',
          'rts',
        ]);
        expect(jsonEncode(decoded), plaintext);
        expect(vector['payload'], decoded);
        final length = utf8.encode(plaintext).length;
        expect(vector['padded_length'], length > 512 ? 1024 : 512);
      }
      final long = vectors.singleWhere((v) => v['name'] == 'long_ids');
      expect(long['padded_length'], 1024);
      expect(long['plaintext'], contains('Zoë 李𝓩'));
    });

    test('only a quote and a backslash are escaped, never a slash, and a '
        'control character in an id is escaped as Python writes it', () {
      expect(vectors.map((v) => v['name']), [
        'known_answer',
        'long_ids',
        'escaped_text',
        'skewed_sender',
      ]);
      final escaped = vectors.singleWhere((v) => v['name'] == 'escaped_text');
      expect(escaped['plaintext'], contains(r'"cname":"Al \"Bo\" \\ C/D"'));
      expect(escaped['plaintext'], contains(r'"rname":"R&D / Ops"'));
      expect(escaped['plaintext'], contains(r'"call":"c3\t\u0001"'));
      expect(
        (escaped['payload']! as Map<String, Object?>)['cname'],
        r'Al "Bo" \ C/D',
      );
    });

    test('the expiry is 45 s after the earlier of the send time and 30 s '
        'after receipt', () {
      for (final vector in vectors) {
        final payload = vector['payload']! as Map<String, Object?>;
        final ts = payload['ts']! as int;
        final rts = payload['rts']! as int;
        final earlier = ts < rts + 30000 ? ts : rts + 30000;
        expect(vector['x'], earlier ~/ 1000 + 45, reason: '${vector['name']}');
      }
    });

    test('a send time more than 30 s after receipt cannot extend the '
        'expiry', () {
      int field(Map<String, Object?> vector, String key) =>
          (vector['payload']! as Map<String, Object?>)[key]! as int;
      final skewed = vectors.singleWhere((v) => v['name'] == 'skewed_sender');
      final skewedTs = field(skewed, 'ts');
      final skewedRts = field(skewed, 'rts');
      expect(skewedTs, greaterThan(skewedRts + 30000));
      expect(skewed['x'], (skewedRts + 30000) ~/ 1000 + 45);
      expect(skewed['x'], isNot(skewedTs ~/ 1000 + 45));
      for (final vector in vectors.where((v) => v != skewed)) {
        final name = '${vector['name']}';
        final ts = field(vector, 'ts');
        expect(
          ts,
          lessThanOrEqualTo(field(vector, 'rts') + 30000),
          reason: name,
        );
        expect(vector['x'], ts ~/ 1000 + 45, reason: name);
      }
    });

    test('each tamper case changes exactly what it names', () {
      final tamper = {
        for (final entry in _list(fixture['tamper'])) entry['name']: entry,
      };
      List<int> bytes(String name) =>
          base64Decode(tamper[name]!['blob']! as String);
      List<int> flip(int index) => [...knownBlob]..[index] ^= 0x01;
      expect(bytes('flipped_tag'), flip(knownBlob.length - 1));
      expect(bytes('flipped_aad_byte'), flip(8));
      expect(bytes('flipped_ciphertext_byte'), flip(21));
      expect(bytes('truncated'), knownBlob.sublist(0, knownBlob.length - 1));
      expect(bytes('short_header'), knownBlob.sublist(0, 8));
      expect(bytes('unpadded_length').sublist(0, 21), knownBlob.sublist(0, 21));
      expect(bytes('unpadded_length'), hasLength(1 + 4 + 4 + 12 + 600 + 16));
      expect(
        () => base64Decode(tamper['not_base64']!['blob']! as String),
        throwsFormatException,
      );
      expect(bytes('unknown_version'), [0x02, ...knownBlob.sublist(1)]);
      expect(bytes('unknown_kid'), [
        0x01,
        0x01,
        0x02,
        0x03,
        0x05,
        ...knownBlob.sublist(5),
      ]);
      expect(
        {for (final entry in tamper.values) entry['name']: entry['expect']},
        {
          'flipped_tag': 'forged',
          'flipped_aad_byte': 'forged',
          'flipped_ciphertext_byte': 'forged',
          'truncated': 'forged',
          'short_header': 'forged',
          'unpadded_length': 'forged',
          'not_base64': 'forged',
          'unknown_version': 'generic',
          'unknown_kid': 'generic',
        },
      );
    });
  });

  group('the name vectors', () {
    final fixture = _fixture('names_v1.json');
    final cases = {
      for (final entry in _list(fixture['cases'])) entry['name']: entry,
    };

    test('each name loses its control and bidi characters, then keeps the '
        'longest run of whole characters that fits 64 bytes', () {
      for (final entry in cases.values) {
        final output = entry['output']! as String;
        expect(
          _normalizedName(entry['input']! as String),
          output,
          reason: '${entry['name']}',
        );
        expect(utf8.encode(output).length, lessThanOrEqualTo(64));
      }
    });

    test('the cases cover the edges the contract names', () {
      expect(cases, hasLength(21));
      String output(String name) => cases[name]!['output']! as String;
      expect(output('ascii_short'), 'Alice');
      expect(output('ascii_exactly_64'), 'a' * 64);
      expect(output('ascii_over_64'), ('abcdefghij' * 7).substring(0, 64));
      expect(output('two_byte_straddles_64'), 'a' * 63);
      expect(output('three_byte_straddles_64'), 'a' * 62);
      expect(output('astral_straddles_64'), 'a' * 61);
      expect(output('emoji_only'), '😀' * 16);
      expect(output('emoji_modifier_split'), '${'a' * 58}👍');
      expect(output('controls_stripped'), 'AliceSmith');
      expect(output('delete_stripped'), 'Anna');
      expect(output('c1_control_stripped'), 'Bobby');
      expect(output('bidi_stripped'), 'evil namex');
      expect(output('strip_before_cut'), 'a' * 60);
      expect(output('joiners_kept'), 'a\u200db\u200cc\ufeffd');
      expect(output('right_to_left_text_kept'), 'مرحبا بك');
      expect(output('only_controls'), '');
      expect(output('empty'), '');
    });

    test('the Arabic letter mark is stripped, and the characters just outside '
        'the strip ranges are kept', () {
      String input(String name) => cases[name]!['input']! as String;
      String output(String name) => cases[name]!['output']! as String;
      expect(input('arabic_letter_mark_stripped').runes, contains(0x061c));
      expect(output('arabic_letter_mark_stripped'), 'Anais');
      const kept = {
        'no_break_space_kept': 0x00a0,
        'just_below_isolates_kept': 0x2065,
        'just_above_isolates_kept': 0x206a,
      };
      for (final entry in kept.entries) {
        final name = entry.key;
        expect(input(name).runes, contains(entry.value), reason: name);
        expect(output(name), input(name), reason: name);
      }
    });
  });

  group('the CallKit UUID vectors', () {
    final fixture = _fixture('call_uuid_v5.json');
    final cases = _list(fixture['cases']);

    test('each is the name-based SHA-1 UUID of room, newline, call', () {
      for (final entry in cases) {
        expect(
          _uuidV5(
            fixture['namespace']! as String,
            '${entry['room_id']}${fixture['separator']}${entry['call_id']}',
          ),
          entry['uuid'],
          reason: '${entry['room_id']} ${entry['call_id']}',
        );
      }
    });

    test('the contract vector is among them', () {
      expect(fixture['namespace'], '5C2B7E0A-3D4F-4B8E-9A61-2F7C8D0E1B34');
      expect(
        cases,
        contains(
          equals({
            'room_id': '!abc:zuno.im',
            'call_id': 'c1',
            'uuid': '76204647-3A1F-568F-8647-458C11FDA59D',
          }),
        ),
      );
    });
  });

  group('the opaque id vectors', () {
    final fixture = _fixture('opaque_ids_v1.json');
    final installKey = base64Decode(fixture['install_key']! as String);
    final cases = _list(fixture['cases']);

    test('each token is the first 32 hex characters of HMAC-SHA256 over the '
        'UTF-8 id', () {
      expect(installKey, _range(0x20, 0x3f));
      for (final entry in cases) {
        final mac = Hmac(
          sha256,
          installKey,
        ).convert(utf8.encode(entry['input']! as String));
        expect(
          mac.toString().substring(0, 32),
          entry['token'],
          reason: '${entry['input']}',
        );
      }
    });

    test('the contract room and event tokens are among them', () {
      final tokens = {for (final c in cases) c['input']: c['token']};
      expect(tokens['!abc:zuno.im'], '2d2de6b6c6565ad95bf365845db19da9');
      expect(tokens[r'$ev1:zuno.im'], 'f79169d67a42d7034d5c3f6a66d7d58a');
    });
  });

  group('the sealed file vectors', () {
    final fixture = _fixture('sealed_file_v1.json');
    final room = _list(fixture['cases']).single;
    final sealed = base64Decode(room['sealed']! as String);

    test('the room title file is the contract vector', () {
      expect(base64Decode(fixture['rm_key']! as String), _range(0x40, 0x5f));
      expect(room['name'], 'rooms/2d2de6b6c6565ad95bf365845db19da9');
      expect(
        room['sealed'],
        'AbCxsrO0tba3uLm6uyryd8SWeEd++0FeFEY0kZd1BCIzgDeMjcTUWTUVisFuBXxqoa2w'
        'uInGZWXlhxQsjztVsh4rqrSJvya9yA8E+DSDhLyqVPaE6R+H1qVL1BvT61RMXEQ+Zakm',
      );
      expect(sealed[0], 0x01);
      expect(sealed.sublist(1, 13), _range(0xb0, 0xbb));
      expect(
        sealed,
        hasLength(
          1 + 12 + utf8.encode(room['plaintext']! as String).length + 16,
        ),
      );
    });

    test('each tamper case changes exactly what it names', () {
      final tamper = {
        for (final entry in _list(fixture['tamper'])) entry['name']: entry,
      };
      List<int> bytes(String name) =>
          base64Decode(tamper[name]!['sealed']! as String);
      List<int> flip(int index) => [...sealed]..[index] ^= 0x01;
      expect(bytes('wrong_name'), sealed);
      expect(tamper['wrong_name']!['file_name'], isNot(room['name']));
      expect(bytes('flipped_tag'), flip(sealed.length - 1));
      expect(bytes('flipped_ciphertext_byte'), flip(13));
      expect(bytes('unknown_version'), [0x02, ...sealed.sublist(1)]);
      expect(bytes('truncated'), sealed.sublist(0, 28));
      expect(tamper.values.map((entry) => entry['expect']).toSet(), {'fail'});
    });
  });
}
