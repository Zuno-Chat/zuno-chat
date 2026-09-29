import 'dart:typed_data';

Uint8List opusCaf({
  required List<List<int>> packets,
  String format = 'opus',
  int channels = 1,
  int priming = 0,
  int? validFrames,
  bool withPacketTable = true,
}) {
  final out = BytesBuilder();
  void chunk(String type, List<int> body) {
    out.add(type.codeUnits);
    out.add((ByteData(8)..setInt64(0, body.length)).buffer.asUint8List());
    out.add(body);
  }

  out.add('caff'.codeUnits);
  out.add([0, 1, 0, 0]);
  final desc = ByteData(32)
    ..setFloat64(0, 48000)
    ..setUint32(20, 960)
    ..setUint32(24, channels);
  desc.buffer.asUint8List().setRange(8, 12, format.codeUnits);
  chunk('desc', desc.buffer.asUint8List());
  if (withPacketTable) {
    final table = BytesBuilder()
      ..add(
        (ByteData(24)
              ..setInt64(0, packets.length)
              ..setInt64(8, validFrames ?? packets.length * 960)
              ..setInt32(16, priming))
            .buffer
            .asUint8List(),
      );
    for (final packet in packets) {
      final size = packet.length;
      final bytes = <int>[size & 0x7f];
      var rest = size >> 7;
      while (rest > 0) {
        bytes.insert(0, (rest & 0x7f) | 0x80);
        rest >>= 7;
      }
      table.add(bytes);
    }
    chunk('pakt', table.toBytes());
  }
  chunk('data', [0, 0, 0, 0, for (final p in packets) ...p]);
  return out.toBytes();
}
