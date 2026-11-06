import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const _besideGap = 12.0;
const _belowGap = 4.0;

class TrailingActionRow extends MultiChildRenderObjectWidget {
  TrailingActionRow({required Widget main, required Widget action, super.key})
    : super(children: [main, action]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTrailingActionRow(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTrailingActionRow).textDirection =
        Directionality.of(context);
  }
}

class _RowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTrailingActionRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RowParentData> {
  _RenderTrailingActionRow(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _main => firstChild!;
  RenderBox get _action => childAfter(_main)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RowParentData) {
      child.parentData = _RowParentData();
    }
  }

  ({Size size, Offset main, Offset action}) _arrange(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final width = constraints.maxWidth;
    final action = layoutChild(_action, BoxConstraints(maxWidth: width));
    final room = width - action.width - _besideGap;
    final besideLeft = _textDirection == TextDirection.rtl;
    final actionX = besideLeft ? 0.0 : width - action.width;

    if (room >= action.width) {
      final main = layoutChild(_main, BoxConstraints.tightFor(width: room));
      final height = math.max(main.height, action.height);
      return (
        size: constraints.constrain(Size(width, height)),
        main: Offset(besideLeft ? width - room : 0, (height - main.height) / 2),
        action: Offset(actionX, (height - action.height) / 2),
      );
    }

    final main = layoutChild(_main, BoxConstraints.tightFor(width: width));
    return (
      size: constraints.constrain(
        Size(width, main.height + _belowGap + action.height),
      ),
      main: Offset.zero,
      action: Offset(actionX, main.height + _belowGap),
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  void performLayout() {
    final arranged = _arrange(constraints, ChildLayoutHelper.layoutChild);
    size = arranged.size;
    (_main.parentData! as _RowParentData).offset = arranged.main;
    (_action.parentData! as _RowParentData).offset = arranged.action;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _main.getMinIntrinsicWidth(height),
    _action.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _main.getMaxIntrinsicWidth(height) +
      _besideGap +
      _action.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _arrange(
    BoxConstraints(maxWidth: width),
    ChildLayoutHelper.dryLayoutChild,
  ).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
