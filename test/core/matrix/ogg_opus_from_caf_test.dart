import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/ogg_opus_from_caf.dart';

import '../../helpers/opus_caf.dart';

class _Page {
  final int flags;
  final int granule;
  final int sequence;
  final List<int> lacing;
  final List<int> body;
  final bool checksumValid;

  _Page(
    this.flags,
    this.granule,
    this.sequence,
    this.lacing,
    this.body,
    this.checksumValid,
  );
}

int _bitwiseCrc(List<int> data) {
  var crc = 0;
  for (final byte in data) {
    crc ^= byte << 24;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80000000) != 0 ? (crc << 1) ^ 0x04c11db7 : crc << 1;
      crc &= 0xffffffff;
    }
  }
  return crc;
}

List<_Page> _pages(Uint8List ogg) {
  final pages = <_Page>[];
  var i = 0;
  while (i < ogg.length) {
    expect(String.fromCharCodes(ogg.sublist(i, i + 4)), 'OggS');
    final header = ByteData.sublistView(ogg, i, i + 27);
    final segments = header.getUint8(26);
    final lacing = ogg.sublist(i + 27, i + 27 + segments);
    final bodyLength = lacing.fold<int>(0, (a, b) => a + b);
    final end = i + 27 + segments + bodyLength;
    final page = Uint8List.fromList(ogg.sublist(i, end));
    final stored = ByteData.sublistView(page).getUint32(22, Endian.little);
    page.setRange(22, 26, [0, 0, 0, 0]);
    pages.add(
      _Page(
        header.getUint8(5),
        header.getInt64(6, Endian.little),
        header.getUint32(18, Endian.little),
        lacing,
        ogg.sublist(i + 27 + segments, end),
        stored == _bitwiseCrc(page),
      ),
    );
    i = end;
  }
  return pages;
}

List<List<int>> _packets(List<_Page> pages) {
  final packets = <List<int>>[];
  var current = <int>[];
  for (final page in pages) {
    var offset = 0;
    for (final value in page.lacing) {
      current.addAll(page.body.sublist(offset, offset + value));
      offset += value;
      if (value < 255) {
        packets.add(current);
        current = <int>[];
      }
    }
  }
  return packets;
}

void main() {
  List<int> packet(int size, int seed) =>
      List<int>.generate(size, (i) => (i + seed) & 0xff);

  test('an Opus recording becomes an Ogg Opus stream with its packets in '
      'order and valid checksums', () {
    final audio = [packet(120, 1), packet(80, 2), packet(200, 3)];

    final pages = _pages(
      oggOpusFromCaf(opusCaf(packets: audio, priming: 312))!,
    );

    expect(pages.every((p) => p.checksumValid), isTrue);
    expect(
      [for (final p in pages) p.sequence],
      [for (var i = 0; i < pages.length; i++) i],
    );
    final packets = _packets(pages);
    final head = ByteData.sublistView(Uint8List.fromList(packets[0]));
    expect(String.fromCharCodes(packets[0].take(8)), 'OpusHead');
    expect(head.getUint8(9), 1);
    expect(head.getUint16(10, Endian.little), 312);
    expect(head.getUint32(12, Endian.little), 48000);
    expect(String.fromCharCodes(packets[1].take(8)), 'OpusTags');
    expect(packets.skip(2), audio);
    expect(pages.first.flags, 0x02);
    expect(pages.first.lacing, hasLength(1));
    expect(pages[1].lacing.length, greaterThanOrEqualTo(1));
  });

  test('the last page ends the stream at the recorded length', () {
    final pages = _pages(
      oggOpusFromCaf(
        opusCaf(
          packets: [packet(50, 1), packet(50, 2), packet(50, 3)],
          priming: 312,
          validFrames: 2500,
        ),
      )!,
    );

    expect(pages.last.flags & 0x04, 0x04);
    expect(pages.last.granule, 312 + 2500);
  });

  test('packets of 255 bytes and more survive the page lacing', () {
    final audio = [packet(255, 1), packet(600, 2), packet(0, 3), packet(1, 4)];

    final packets = _packets(_pages(oggOpusFromCaf(opusCaf(packets: audio))!));

    expect(packets.skip(2), audio);
  });

  test('a long recording spreads over pages of at most 255 segments', () {
    final audio = [for (var i = 0; i < 400; i++) packet(300, i)];

    final pages = _pages(oggOpusFromCaf(opusCaf(packets: audio))!);

    expect(pages.length, greaterThan(3));
    expect(pages.every((p) => p.lacing.length <= 255), isTrue);
    expect(pages.every((p) => p.checksumValid), isTrue);
    expect(_packets(pages).skip(2), audio);
    final granules = [for (final p in pages.skip(2)) p.granule];
    expect(granules, orderedEquals([...granules]..sort()));
  });

  test('anything that is not an Opus recording is refused', () {
    expect(oggOpusFromCaf(Uint8List.fromList('not audio'.codeUnits)), isNull);
    expect(
      oggOpusFromCaf(opusCaf(packets: [packet(10, 1)], format: 'aac ')),
      isNull,
    );
    expect(
      oggOpusFromCaf(opusCaf(packets: [packet(10, 1)], withPacketTable: false)),
      isNull,
    );
    expect(oggOpusFromCaf(opusCaf(packets: const [])), isNull);
  });
}
