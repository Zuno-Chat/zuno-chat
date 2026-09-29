import 'dart:math' show min;
import 'dart:typed_data';

const _opusSampleRate = 48000;
const _serial = 0x5a554e4f;
const _vendor = 'Zuno';
const _maxSegments = 255;

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var r = i << 24;
    for (var bit = 0; bit < 8; bit++) {
      r = (r & 0x80000000) != 0 ? (r << 1) ^ 0x04c11db7 : r << 1;
    }
    table[i] = r & 0xffffffff;
  }
  return table;
}();

int _crc(Uint8List data) {
  var crc = 0;
  for (final byte in data) {
    crc = ((crc << 8) ^ _crcTable[((crc >> 24) ^ byte) & 0xff]) & 0xffffffff;
  }
  return crc;
}

typedef _CafOpus = ({
  int channels,
  int framesPerPacket,
  int priming,
  int validFrames,
  List<Uint8List> packets,
});

_CafOpus? _readCaf(Uint8List bytes) {
  if (bytes.length < 8 || String.fromCharCodes(bytes.sublist(0, 4)) != 'caff') {
    return null;
  }
  final view = ByteData.sublistView(bytes);
  final chunks = <String, Uint8List>{};
  var offset = 8;
  while (offset + 12 <= bytes.length) {
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    var size = view.getInt64(offset + 4);
    offset += 12;
    if (size == -1) size = bytes.length - offset;
    if (size < 0 || offset + size > bytes.length) return null;
    chunks[type] = Uint8List.sublistView(bytes, offset, offset + size);
    offset += size;
  }

  final desc = chunks['desc'];
  final table = chunks['pakt'];
  final data = chunks['data'];
  if (desc == null || desc.length < 32 || table == null || data == null) {
    return null;
  }
  final d = ByteData.sublistView(desc);
  final format = String.fromCharCodes(desc.sublist(8, 12));
  final framesPerPacket = d.getUint32(20);
  final channels = d.getUint32(24);
  if (format != 'opus' ||
      d.getFloat64(0) != _opusSampleRate ||
      framesPerPacket == 0 ||
      channels < 1 ||
      channels > 2 ||
      table.length < 24 ||
      data.length < 4) {
    return null;
  }

  final t = ByteData.sublistView(table);
  final count = t.getInt64(0);
  final validFrames = t.getInt64(8);
  final priming = t.getInt32(16);
  if (count <= 0 || validFrames <= 0 || priming < 0) return null;

  final packets = <Uint8List>[];
  var cursor = 24;
  var audio = 4;
  for (var i = 0; i < count; i++) {
    var size = 0;
    int byte;
    do {
      if (cursor >= table.length) return null;
      byte = table[cursor++];
      size = (size << 7) | (byte & 0x7f);
    } while (byte & 0x80 != 0);
    if (audio + size > data.length) return null;
    packets.add(Uint8List.sublistView(data, audio, audio + size));
    audio += size;
  }
  return (
    channels: channels,
    framesPerPacket: framesPerPacket,
    priming: priming,
    validFrames: validFrames,
    packets: packets,
  );
}

Uint8List _uint32le(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

List<int> _lacing(int size) => [
  for (var i = 0; i < size ~/ 255; i++) 255,
  size % 255,
];

Uint8List _page({
  required int sequence,
  required int granule,
  required int flags,
  required List<Uint8List> packets,
}) {
  final lacing = [for (final p in packets) ..._lacing(p.length)];
  final header = ByteData(27)
    ..setUint32(0, 0x4f676753)
    ..setUint8(4, 0)
    ..setUint8(5, flags)
    ..setInt64(6, granule, Endian.little)
    ..setUint32(14, _serial, Endian.little)
    ..setUint32(18, sequence, Endian.little)
    ..setUint8(26, lacing.length);
  final page = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(lacing);
  for (final p in packets) {
    page.add(p);
  }
  final bytes = page.toBytes();
  ByteData.sublistView(bytes).setUint32(22, _crc(bytes), Endian.little);
  return bytes;
}

Uint8List? oggOpusFromCaf(Uint8List caf) {
  final opus = _readCaf(caf);
  if (opus == null) return null;
  if (opus.packets.any((p) => _lacing(p.length).length > _maxSegments)) {
    return null;
  }

  final head = ByteData(19)
    ..setUint32(0, 0x4f707573)
    ..setUint32(4, 0x48656164)
    ..setUint8(8, 1)
    ..setUint8(9, opus.channels)
    ..setUint16(10, opus.priming, Endian.little)
    ..setUint32(12, _opusSampleRate, Endian.little)
    ..setInt16(16, 0, Endian.little)
    ..setUint8(18, 0);
  final tags = BytesBuilder()
    ..add('OpusTags'.codeUnits)
    ..add(_uint32le(_vendor.length))
    ..add(_vendor.codeUnits)
    ..add(_uint32le(0));

  final out = BytesBuilder(copy: false)
    ..add(
      _page(
        sequence: 0,
        granule: 0,
        flags: 0x02,
        packets: [head.buffer.asUint8List()],
      ),
    )
    ..add(_page(sequence: 1, granule: 0, flags: 0, packets: [tags.toBytes()]));

  final end = opus.priming + opus.validFrames;
  var sequence = 2;
  var frames = 0;
  var pending = <Uint8List>[];
  var segments = 0;
  for (final packet in opus.packets) {
    final needed = _lacing(packet.length).length;
    if (segments + needed > _maxSegments) {
      out.add(
        _page(
          sequence: sequence++,
          granule: frames,
          flags: 0,
          packets: pending,
        ),
      );
      pending = <Uint8List>[];
      segments = 0;
    }
    pending.add(packet);
    segments += needed;
    frames += opus.framesPerPacket;
  }
  out.add(
    _page(
      sequence: sequence,
      granule: min(frames, end),
      flags: 0x04,
      packets: pending,
    ),
  );
  return out.toBytes();
}
