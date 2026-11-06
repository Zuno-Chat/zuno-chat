import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

typedef DrawableProbe = Future<List<bool>> Function(List<String> emoji);

const _fontSize = 16.0;
const _cell = 24;
const _columns = 10;
const _layoutBatch = 20;
const _readBatch = 100;
const _reference = '😀';
const _widthTolerance = 0.08;
const _channelTolerance = 16;
const _first = ui.Color(0xFFFF0000);
const _second = ui.Color(0xFF0000FF);

bool oneGlyph(double width, double reference) =>
    (width - reference).abs() <= reference * _widthTolerance;

bool sameInkedCell(
  ByteData pixels,
  int imageWidth, {
  required int left,
  required int otherLeft,
  required int top,
  required int size,
}) {
  final words = pixels.buffer.asUint32List(
    pixels.offsetInBytes,
    pixels.lengthInBytes ~/ 4,
  );
  var inked = false;
  for (var y = top; y < top + size; y++) {
    for (var x = 0; x < size; x++) {
      final p = words[y * imageWidth + left + x];
      final q = words[y * imageWidth + otherLeft + x];
      if (p != 0 || q != 0) inked = true;
      if (p != q && !_closeEnough(p, q)) return false;
    }
  }
  return inked;
}

bool _closeEnough(int p, int q) {
  for (var shift = 0; shift < 32; shift += 8) {
    if ((((p >> shift) & 0xFF) - ((q >> shift) & 0xFF)).abs() >
        _channelTolerance) {
      return false;
    }
  }
  return true;
}

Future<List<bool>> probeDrawable(List<String> emoji) async {
  final scheduler = SchedulerBinding.instance;
  final referenceWidth = await scheduler.scheduleTask(
    _referenceWidth,
    Priority.animation,
  );
  final result = <bool>[];
  for (var start = 0; start < emoji.length; start += _readBatch) {
    final chunk = emoji.sublist(
      start,
      math.min(start + _readBatch, emoji.length),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final widths = <double>[];
    for (var from = 0; from < chunk.length; from += _layoutBatch) {
      final to = math.min(from + _layoutBatch, chunk.length);
      widths.addAll(
        await scheduler.scheduleTask(
          () => _draw(canvas, chunk, from, to),
          Priority.animation,
        ),
      );
    }
    final pixels = await _rasterize(recorder.endRecording(), chunk.length);
    for (var from = 0; from < chunk.length; from += _layoutBatch) {
      final to = math.min(from + _layoutBatch, chunk.length);
      result.addAll(
        await scheduler.scheduleTask(
          () => _judge(widths, pixels, from, to, referenceWidth),
          Priority.animation,
        ),
      );
    }
  }
  return result;
}

double _referenceWidth() {
  final reference = _paragraph(_reference, _first);
  final width = reference.longestLine;
  reference.dispose();
  return width;
}

ui.Paragraph _paragraph(String text, ui.Color color) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: _fontSize))
    ..pushStyle(ui.TextStyle(color: color, fontSize: _fontSize))
    ..addText(text);
  return builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
}

List<double> _draw(ui.Canvas canvas, List<String> chunk, int from, int to) {
  final widths = <double>[];
  for (var i = from; i < to; i++) {
    final left = (i % _columns * _cell).toDouble();
    final top = (i ~/ _columns * _cell).toDouble();
    for (final (offset, color) in [(0, _first), (_columns * _cell, _second)]) {
      final cell = ui.Rect.fromLTWH(
        left + offset,
        top,
        _cell.toDouble(),
        _cell.toDouble(),
      );
      final paragraph = _paragraph(chunk[i], color);
      if (offset == 0) widths.add(paragraph.longestLine);
      canvas
        ..save()
        ..clipRect(cell)
        ..drawParagraph(paragraph, cell.topLeft + const ui.Offset(2, 1))
        ..restore();
      paragraph.dispose();
    }
  }
  return widths;
}

Future<ByteData> _rasterize(ui.Picture picture, int count) async {
  final image = await picture.toImage(
    2 * _columns * _cell,
    (count + _columns - 1) ~/ _columns * _cell,
  );
  picture.dispose();
  try {
    final pixels = await image.toByteData();
    if (pixels == null) throw StateError('No pixels to compare');
    return pixels;
  } finally {
    image.dispose();
  }
}

List<bool> _judge(
  List<double> widths,
  ByteData pixels,
  int from,
  int to,
  double referenceWidth,
) => [
  for (var i = from; i < to; i++)
    oneGlyph(widths[i], referenceWidth) &&
        sameInkedCell(
          pixels,
          2 * _columns * _cell,
          left: i % _columns * _cell,
          otherLeft: _columns * _cell + i % _columns * _cell,
          top: i ~/ _columns * _cell,
          size: _cell,
        ),
];
