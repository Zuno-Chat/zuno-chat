import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/async/serial_lock.dart';
import '../../../core/calls/active_call_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/navigation/zuno_links.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/onboarding/onboarding_step.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/updates/app_version.dart';
import '../../../core/updates/update_notice.dart';

class UpdatePrompt extends ConsumerStatefulWidget {
  const UpdatePrompt({super.key, required this.prompts, required this.child});

  final SerialLock prompts;
  final Widget child;

  @override
  ConsumerState<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<UpdatePrompt> {
  late final AppLifecycleListener _lifecycle;
  var _onTop = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
    ref.listenManual(updateNoticeProvider, (_, _) => _tryShow());
    ref.listenManual(activeCallProvider, (_, _) => _tryShow());
    ref.listenManual(onboardingStepsProvider, (_, _) => _tryShow());
    _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onTop = ModalRoute.isCurrentOf(context) ?? false;
    if (_onTop) _tryShow();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _check() => unawaited(ref.read(updateNoticeProvider.notifier).check());

  bool _mayShow() {
    if (!_onTop || widget.prompts.busy) return false;
    final call = ref.read(activeCallProvider);
    if (call != null && !call.ending) return false;
    return !promptDefersToOnboarding(
      flow: ref.read(onboardingStoreProvider).flow,
      pendingSteps: ref.read(onboardingStepsProvider).value,
    );
  }

  void _tryShow() {
    if (ref.read(updateNoticeProvider) != null) unawaited(_show());
  }

  Future<void> _show() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_mayShow()) return;
    final update = ref.read(updateNoticeProvider);
    if (update == null) return;
    final notice = ref.read(updateNoticeProvider.notifier);
    await widget.prompts.run(() async {
      if (!mounted) return;
      final l10n = context.l10n;
      final accepted = await confirm(
        context,
        title: l10n.updateNoticeTitle,
        body: l10n.updateNoticeBody(versionOfBuild(update.build)),
        confirmLabel: l10n.updateNoticeUpdate,
        cancelLabel: l10n.commonNotNow,
        tone: ConfirmTone.primary,
      );
      await notice.dismiss(update.build);
      if (accepted && mounted) {
        await openLink(context, update.link, openUrl: openExternally);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
