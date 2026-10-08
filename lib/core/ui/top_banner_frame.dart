import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'zuno_motion.dart';

class TopBannerFrame extends StatefulWidget {
  final List<Widget?> banners;
  final Widget child;

  const TopBannerFrame({required this.banners, required this.child, super.key});

  @override
  State<TopBannerFrame> createState() => _TopBannerFrameState();
}

class _TopBannerFrameState extends State<TopBannerFrame>
    with TickerProviderStateMixin {
  final _slots = <_BannerSlot>[];

  @override
  void initState() {
    super.initState();
    _follow(animate: false);
  }

  @override
  void didUpdateWidget(TopBannerFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _follow(animate: !MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  void _follow({required bool animate}) {
    while (_slots.length < widget.banners.length) {
      _slots.add(_BannerSlot(this, onGone: () => setState(() {})));
    }
    for (final (index, slot) in _slots.indexed) {
      slot.show(widget.banners.elementAtOrNull(index), animate: animate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final slot in _slots)
        if (slot.banner != null) slot,
    ];
    return _BannerLayout(
      inset: MediaQuery.paddingOf(context).top,
      reveals: [for (final slot in shown) slot.reveal],
      children: [
        widget.child,
        for (final slot in shown)
          KeyedSubtree(key: ObjectKey(slot), child: slot.banner!),
      ],
    );
  }
}

class _BannerSlot {
  final AnimationController _controller;
  late final CurvedAnimation reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );
  Widget? banner;

  _BannerSlot(TickerProvider vsync, {required VoidCallback onGone})
    : _controller = AnimationController(
        vsync: vsync,
        duration: ZunoDurations.page,
      ) {
    _controller.addStatusListener((status) {
      if (status.isDismissed && banner != null) {
        banner = null;
        onGone();
      }
    });
  }

  void show(Widget? next, {required bool animate}) {
    if (!animate) {
      banner = next;
      _controller.value = next == null ? 0 : 1;
    } else if (next == null) {
      _controller.reverse();
    } else {
      banner = next;
      _controller.forward();
    }
  }

  void dispose() {
    reveal.dispose();
    _controller.dispose();
  }
}

class _BannerLayout extends MultiChildRenderObjectWidget {
  final double inset;
  final List<Animation<double>> reveals;

  const _BannerLayout({
    required this.inset,
    required this.reveals,
    required super.children,
  });

  @override
  _RenderBannerLayout createRenderObject(BuildContext context) =>
      _RenderBannerLayout(inset: inset, reveals: reveals);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBannerLayout renderObject,
  ) {
    renderObject
      ..inset = inset
      ..reveals = reveals;
  }
}

class _BannerParentData extends ContainerBoxParentData<RenderBox> {
  Rect? visible;
}

class _RenderBannerLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BannerParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _BannerParentData> {
  _RenderBannerLayout({required this._inset, required this._reveals});

  final _clips = <LayerHandle<ClipRectLayer>>[];

  double _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsLayout();
  }

  List<Animation<double>> _reveals;
  set reveals(List<Animation<double>> value) {
    if (listEquals(value, _reveals)) return;
    if (attached) _unlisten();
    _reveals = value;
    if (attached) _listen();
    markNeedsLayout();
  }

  void _listen() {
    for (final reveal in _reveals) {
      reveal.addListener(markNeedsLayout);
    }
  }

  void _unlisten() {
    for (final reveal in _reveals) {
      reveal.removeListener(markNeedsLayout);
    }
  }

  RenderBox get _content => firstChild!;

  Iterable<RenderBox> get _banners sync* {
    var banner = childAfter(_content);
    while (banner != null) {
      yield banner;
      banner = childAfter(banner);
    }
  }

  static _BannerParentData _dataOf(RenderBox child) =>
      child.parentData! as _BannerParentData;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void dispose() {
    for (final clip in _clips) {
      clip.layer = null;
    }
    _clips.clear();
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BannerParentData) {
      child.parentData = _BannerParentData();
    }
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    var covered = 0.0;
    for (final (index, banner) in _banners.indexed) {
      banner.layout(
        BoxConstraints.tightFor(width: size.width),
        parentUsesSize: true,
      );
      final height = banner.size.height;
      final visible =
          math.max(0.0, height - math.min(_inset, covered)) *
          _reveals[index].value;
      _dataOf(banner)
        ..offset = Offset(0, covered + visible - height)
        ..visible = visible < height
            ? Rect.fromLTRB(0, height - visible, size.width, height)
            : null;
      covered += visible;
    }
    final top = math.max(0.0, covered - _inset);
    _content.layout(
      BoxConstraints.tight(Size(size.width, math.max(0.0, size.height - top))),
    );
    _dataOf(_content).offset = Offset(0, top);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_content, offset + _dataOf(_content).offset);
    var clipped = 0;
    for (final banner in _banners) {
      final data = _dataOf(banner);
      final visible = data.visible;
      if (visible == null) {
        context.paintChild(banner, offset + data.offset);
        continue;
      }
      if (visible.isEmpty) continue;
      if (_clips.length == clipped) _clips.add(LayerHandle<ClipRectLayer>());
      final clip = _clips[clipped++];
      clip.layer = context.pushClipRect(
        needsCompositing,
        offset + data.offset,
        visible,
        (context, offset) => context.paintChild(banner, offset),
        oldLayer: clip.layer,
      );
    }
    while (_clips.length > clipped) {
      _clips.removeLast().layer = null;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final banner in _banners) {
      final data = _dataOf(banner);
      final visible = data.visible ?? Offset.zero & banner.size;
      if (!visible.contains(position - data.offset)) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, position) =>
            banner.hitTest(result, position: position),
      );
      if (hit) return true;
    }
    return result.addWithPaintOffset(
      offset: _dataOf(_content).offset,
      position: position,
      hitTest: (result, position) =>
          _content.hitTest(result, position: position),
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      (child.parentData! as _BannerParentData).visible;
}
