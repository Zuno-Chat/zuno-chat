import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool isInFront(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    state == AppLifecycleState.inactive;

mixin VisibleInFront<T extends StatefulWidget> on State<T> {
  ValueListenable<TickerModeData>? _ticker;
  late final AppLifecycleListener _lifecycle;

  bool get visibleInFront =>
      (_ticker?.value.enabled ?? true) &&
      isInFront(WidgetsBinding.instance.lifecycleState);

  void onVisibleInFrontChanged();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (_) => onVisibleInFrontChanged(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = TickerMode.getValuesNotifier(context);
    if (!identical(ticker, _ticker)) {
      _ticker?.removeListener(onVisibleInFrontChanged);
      _ticker = ticker..addListener(onVisibleInFrontChanged);
    }
    onVisibleInFrontChanged();
  }

  @override
  void dispose() {
    _ticker?.removeListener(onVisibleInFrontChanged);
    _lifecycle.dispose();
    super.dispose();
  }
}
