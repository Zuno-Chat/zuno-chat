import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class KeepClearAreas extends ChangeNotifier {
  final _areas = <_RenderKeepClearArea>{};
  RenderBox? _host;
  double _hostBottomInset = 0;
  double _bottom = 0;
  bool _measureScheduled = false;
  bool _disposed = false;

  double get bottom => _bottom;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _measure(notify: false);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _add(_RenderKeepClearArea area) {
    if (_areas.add(area)) _scheduleMeasure();
  }

  void _remove(_RenderKeepClearArea area) {
    if (_areas.remove(area)) _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (_measureScheduled || _disposed || !hasListeners) return;
    _measureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (_disposed || !hasListeners) return;
      _measure(notify: true);
      _scheduleMeasure();
    });
  }

  void _measure({required bool notify}) {
    final host = _host;
    var bottom = 0.0;
    if (host != null && host.attached && host.hasSize) {
      final contentBottom = host.size.height - _hostBottomInset;
      for (final area in _areas) {
        final measured = area._measured;
        if (!measured.attached || !measured.hasSize) continue;
        final top = measured.localToGlobal(Offset.zero, ancestor: host).dy;
        bottom = math.max(bottom, contentBottom - top);
      }
    }
    if (bottom == _bottom) return;
    _bottom = bottom;
    if (notify) notifyListeners();
  }
}

class KeepClearScope extends StatefulWidget {
  final Widget child;

  const KeepClearScope({required this.child, super.key});

  static KeepClearAreas? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_KeepClearInherited>()?.areas;

  @override
  State<KeepClearScope> createState() => _KeepClearScopeState();
}

class _KeepClearScopeState extends State<KeepClearScope> {
  final _areas = KeepClearAreas();

  @override
  void dispose() {
    _areas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _KeepClearInherited(
    areas: _areas,
    child: _KeepClearHost(
      areas: _areas,
      bottomInset: MediaQuery.viewInsetsOf(context).bottom,
      child: widget.child,
    ),
  );
}

class _KeepClearInherited extends InheritedWidget {
  final KeepClearAreas areas;

  const _KeepClearInherited({required this.areas, required super.child});

  @override
  bool updateShouldNotify(_KeepClearInherited oldWidget) =>
      !identical(areas, oldWidget.areas);
}

class _KeepClearHost extends SingleChildRenderObjectWidget {
  final KeepClearAreas areas;
  final double bottomInset;

  const _KeepClearHost({
    required this.areas,
    required this.bottomInset,
    required super.child,
  });

  @override
  _RenderKeepClearHost createRenderObject(BuildContext context) =>
      _RenderKeepClearHost(areas)..bottomInset = bottomInset;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderKeepClearHost renderObject,
  ) {
    renderObject.bottomInset = bottomInset;
  }
}

class _RenderKeepClearHost extends RenderProxyBox {
  _RenderKeepClearHost(this._areas);

  final KeepClearAreas _areas;

  set bottomInset(double value) => _areas._hostBottomInset = value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _areas._host = this;
  }

  @override
  void detach() {
    if (identical(_areas._host, this)) _areas._host = null;
    super.detach();
  }
}

class KeepClearArea extends SingleChildRenderObjectWidget {
  final bool wholeSurface;

  const KeepClearArea({required super.child, super.key}) : wholeSurface = false;

  const KeepClearArea.surface({required super.child, super.key})
    : wholeSurface = true;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKeepClearArea(
    KeepClearScope.maybeOf(context),
    TickerMode.valuesOf(context).enabled,
    wholeSurface,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderKeepClearArea)
      ..wholeSurface = wholeSurface
      ..follow(
        KeepClearScope.maybeOf(context),
        TickerMode.valuesOf(context).enabled,
      );
  }
}

class _RenderKeepClearArea extends RenderProxyBox {
  _RenderKeepClearArea(this._areas, this._onstage, this.wholeSurface);

  KeepClearAreas? _areas;
  bool _onstage;
  bool wholeSurface;

  RenderBox get _measured {
    if (!wholeSurface) return this;
    for (RenderObject? node = parent; node != null; node = node.parent) {
      if (node is RenderPhysicalShape || node is RenderPhysicalModel) {
        return node as RenderBox;
      }
    }
    return this;
  }

  void follow(KeepClearAreas? areas, bool onstage) {
    if (identical(areas, _areas) && onstage == _onstage) return;
    if (attached) _areas?._remove(this);
    _areas = areas;
    _onstage = onstage;
    if (attached && _onstage) _areas?._add(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_onstage) _areas?._add(this);
  }

  @override
  void detach() {
    _areas?._remove(this);
    super.detach();
  }
}
