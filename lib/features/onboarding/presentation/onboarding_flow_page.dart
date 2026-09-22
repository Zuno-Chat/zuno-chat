import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
import '../../../core/notifications/notification_permission.dart';
import '../../../core/notifications/notification_permission_provider.dart';
import '../../../core/onboarding/onboarding_provider.dart';
import '../../../core/onboarding/onboarding_step.dart';
import '../../../core/push/unified_push_distributor_names.dart';
import '../../../core/security/account_security_status.dart';
import '../../../core/security/security_prompt_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/keyboard.dart';
import '../../../core/ui/step_hero.dart';
import '../../../core/ui/step_layout.dart';
import '../../settings/presentation/secure_backup_page.dart';
import '../../verification/presentation/approve_this_device_page.dart';

const _avatarMaxDimension = 512;

const onboardingDotsKey = ValueKey('onboarding-dots');

class OnboardingFlowPage extends ConsumerStatefulWidget {
  final List<OnboardingStep> steps;

  const OnboardingFlowPage({required this.steps, super.key});

  @override
  ConsumerState<OnboardingFlowPage> createState() => _OnboardingFlowPageState();
}

class _OnboardingFlowPageState extends ConsumerState<OnboardingFlowPage> {
  final _pages = PageController();
  final _shown = <OnboardingStep>{};
  late List<OnboardingStep> _steps = List.of(widget.steps);
  int _index = 0;
  bool _closing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _markShown(OnboardingStep step) async {
    if (!_shown.add(step)) return;
    if (step == OnboardingStep.setUpRecovery) {
      await ref.read(securityPromptStoreProvider).markPrompted();
    }
    final userId = ref.read(matrixClientProvider).userID;
    if (userId != null) {
      await ref.read(onboardingStoreProvider).markShown(userId, step);
    }
  }

  Future<void> _advance() async {
    closeKeyboard();
    final index = _index;
    await _markShown(_steps[index]);
    if (!mounted) return;
    if (index + 1 >= _steps.length) {
      _close();
      return;
    }
    await _pages.animateToPage(
      index + 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  Future<void> _deliveryChosen(NotificationDeliveryMode mode) async {
    final needsBattery = await needsBatteryExemptionFor(mode);
    if (!mounted) return;
    setState(() {
      _steps = stepsAfterDeliveryChoice(
        _steps,
        needsBatteryExemption: needsBattery,
      );
    });
    await _advance();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 12),
                  child: TextButton(
                    onPressed: _advance,
                    child: const Text('Skip'),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _index = index),
                  itemCount: steps.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _StepPage(
                      step: steps[index],
                      onDone: _advance,
                      onDeliveryChosen: _deliveryChosen,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: steps.length > 1
                    ? Center(
                        child: _StepDots(
                          key: onboardingDotsKey,
                          count: steps.length,
                          current: _index,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final OnboardingStep step;
  final Future<void> Function() onDone;
  final Future<void> Function(NotificationDeliveryMode) onDeliveryChosen;

  const _StepPage({
    required this.step,
    required this.onDone,
    required this.onDeliveryChosen,
  });

  @override
  Widget build(BuildContext context) => switch (step) {
    OnboardingStep.welcome => _WelcomeStep(onDone: onDone),
    OnboardingStep.profile => _ProfileStep(onDone: onDone),
    OnboardingStep.notifications => _NotificationsStep(onDone: onDone),
    OnboardingStep.deliveryMethod => _DeliveryStep(onChosen: onDeliveryChosen),
    OnboardingStep.batteryExemption => _BatteryStep(onDone: onDone),
    OnboardingStep.approveDevice => _SecurityStep(
      status: AccountSecurityStatus.deviceLocked,
      onDone: onDone,
    ),
    OnboardingStep.setUpRecovery => _SecurityStep(
      status: AccountSecurityStatus.noRecovery,
      onDone: onDone,
    ),
  };
}

class _StepDots extends StatelessWidget {
  final int count;
  final int current;

  const _StepDots({required this.count, required this.current, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == current ? 20 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: i == current ? colors.primary : colors.outlineVariant,
            ),
          ),
      ],
    );
  }
}

class _StepScaffold extends StatelessWidget {
  final IconData? icon;
  final Widget? hero;
  final String title;
  final String body;
  final List<Widget> children;
  final Widget action;

  const _StepScaffold({
    this.icon,
    this.hero,
    required this.title,
    required this.body,
    required this.action,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    return StepLayout(
      hero: hero ?? StepHero(icon: icon),
      title: title,
      body: body,
      padding: const EdgeInsets.only(bottom: 8),
      actions: [action],
      children: children,
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  final Future<void> Function() onDone;

  const _WelcomeStep({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      hero: StepHero(
        child: SvgPicture.asset(
          'assets/logo/zuno-mark-amber.svg',
          width: 56,
          height: 56,
        ),
      ),
      title: 'Welcome to Zuno',
      body:
          'Many chat apps are paid for with data about the people who use '
          'them. Zuno has no advertisers and no investors. Your messages are '
          'end-to-end encrypted, and it works like any chat app.',
      action: FilledButton(
        onPressed: () => onDone(),
        child: const Text('Get started'),
      ),
    );
  }
}

class _DeliveryStep extends ConsumerStatefulWidget {
  final Future<void> Function(NotificationDeliveryMode) onChosen;

  const _DeliveryStep({required this.onChosen});

  @override
  ConsumerState<_DeliveryStep> createState() => _DeliveryStepState();
}

class _DeliveryStepState extends ConsumerState<_DeliveryStep> {
  late NotificationDeliveryMode _selected = ref.read(
    notificationDeliveryModeProvider,
  );
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final previous = ref.read(notificationDeliveryModeProvider);
    if (_selected != previous) {
      await ref.read(notificationDeliveryModeProvider.notifier).set(_selected);
      unawaited(kickOffDeliveryMode(ref.read(matrixClientProvider), _selected));
    }
    if (mounted) setState(() => _saving = false);
    await widget.onChosen(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.send_outlined,
      title: 'How should messages reach you?',
      body:
          'This decides how Zuno hears about new messages and calls while '
          'it is closed. You can change it later in Settings.',
      action: FilledButton(
        onPressed: _saving ? null : _confirm,
        child: const Text('Continue'),
      ),
      children: [
        RadioGroup<NotificationDeliveryMode>(
          groupValue: _selected,
          onChanged: (mode) {
            if (mode != null) setState(() => _selected = mode);
          },
          child: Column(
            children: [
              for (final mode in NotificationDeliveryMode.values)
                RadioListTile<NotificationDeliveryMode>(
                  value: mode,
                  title: Text(mode.label),
                  subtitle: Text(mode.description),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStep extends ConsumerStatefulWidget {
  final Future<void> Function() onDone;

  const _ProfileStep({required this.onDone});

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<_ProfileStep> {
  final _name = TextEditingController();
  MatrixImageFile? _avatar;
  bool _saving = false;

  bool get _canSave => _name.text.trim().isNotEmpty || _avatar != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final client = ref.read(matrixClientProvider);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    final shrunk = await MatrixImageFile.shrink(
      bytes: await picked.readAsBytes(),
      name: picked.name,
      maxDimension: _avatarMaxDimension,
      nativeImplementations: client.nativeImplementations,
    );
    if (!mounted) return;
    setState(() => _avatar = shrunk);
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    closeKeyboard();
    final name = _name.text.trim();
    final avatar = _avatar;
    setState(() => _saving = true);
    final client = ref.read(matrixClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (name.isNotEmpty) {
        await client.setProfileField(client.userID!, 'displayname', {
          'displayname': name,
        });
      }
      if (avatar != null) await client.setAvatar(avatar);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Not saved. You can set it later in Settings.'),
        ),
      );
      debugPrint('zuno/onboarding: profile save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatar = _avatar;
    return _StepScaffold(
      hero: Stack(
        children: [
          StepHero(
            icon: Icons.person_outline,
            image: avatar == null ? null : MemoryImage(avatar.bytes),
            onTap: _saving ? null : _pickAvatar,
            semanticLabel: avatar == null ? 'Add a photo' : 'Change photo',
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _saving ? null : _pickAvatar,
              excludeFromSemantics: true,
              child: Material(
                color: colors.primaryContainer,
                shape: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.photo_camera_outlined,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      title: 'What should people call you?',
      body:
          'This is the name and photo people see in chats. You can change '
          'both later.',
      action: FilledButton(
        onPressed: _saving || !_canSave ? null : _save,
        child: _saving
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
      children: [
        TextField(
          autofillHints: null,
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
      ],
    );
  }
}

class _NotificationsStep extends ConsumerStatefulWidget {
  final Future<void> Function() onDone;

  const _NotificationsStep({required this.onDone});

  @override
  ConsumerState<_NotificationsStep> createState() => _NotificationsStepState();
}

class _NotificationsStepState extends ConsumerState<_NotificationsStep>
    with WidgetsBindingObserver {
  bool _asking = false;
  bool _needsFullScreen = false;
  PermissionStatus _statusBeforeAsking = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatusBeforeAsking());
  }

  Future<void> _refreshStatusBeforeAsking() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _statusBeforeAsking = status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsFullScreen) {
      unawaited(_finishIfFullScreenAllowed());
    }
  }

  Future<void> _finishIfFullScreenAllowed() async {
    final allowed = await CallNotificationService.instance
        .canUseFullScreenIntent();
    if (allowed && mounted) await widget.onDone();
  }

  Future<void> _request() async {
    setState(() => _asking = true);
    try {
      final previous = _statusBeforeAsking;
      final status = await Permission.notification.request();
      await ref.read(notificationsAllowedProvider.notifier).refresh();
      if (ref.read(notificationDeliveryModeProvider) ==
              NotificationDeliveryMode.backgroundService &&
          shouldRefreshBackgroundSync(
            previousStatus: previous,
            newStatus: status,
          )) {
        BackgroundSyncService.instance.start();
      }
      if (!mounted) return;
      if (!status.isGranted) {
        await widget.onDone();
        return;
      }
      final fullScreenAllowed = await CallNotificationService.instance
          .canUseFullScreenIntent();
      if (!mounted) return;
      if (fullScreenAllowed) {
        await widget.onDone();
        return;
      }
      setState(() => _needsFullScreen = true);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needsFullScreen) {
      return _StepScaffold(
        icon: Icons.phonelink_ring_outlined,
        title: 'Let calls take over the screen',
        body:
            'Android keeps this permission in its own settings screen. Without '
            'it, a call on a locked device shows as a small banner instead of '
            'a ringing screen.',
        action: FilledButton(
          onPressed: () =>
              CallNotificationService.instance.openFullScreenIntentSettings(),
          child: const Text('Open settings'),
        ),
      );
    }

    return _StepScaffold(
      icon: Icons.notifications_none_outlined,
      title: 'Hear about new messages',
      body:
          "Zuno needs Android's permission to show new messages and ring for "
          "calls.",
      action: FilledButton(
        onPressed: _asking ? null : _request,
        child: const Text('Turn on notifications'),
      ),
    );
  }
}

class _BatteryStep extends ConsumerStatefulWidget {
  final Future<void> Function() onDone;

  const _BatteryStep({required this.onDone});

  @override
  ConsumerState<_BatteryStep> createState() => _BatteryStepState();
}

class _BatteryStepState extends ConsumerState<_BatteryStep>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(unifiedPushDeliveryProvider.refreshDistributorBattery());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_finishIfAllowed());
  }

  Future<void> _finishIfAllowed() async {
    final mode = ref.read(notificationDeliveryModeProvider);
    final stillNeeded = await needsBatteryExemptionFor(mode);
    if (!stillNeeded && mounted) await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final forUnifiedPush =
        ref.watch(notificationDeliveryModeProvider) ==
        NotificationDeliveryMode.unifiedPush;
    return _StepScaffold(
      icon: Icons.battery_saver_outlined,
      title: 'Let Zuno wake up',
      body:
          'Android puts apps to sleep when your device has been locked for a '
          'while. Zuno needs an exception, or messages and calls will not '
          'reach you until you open it.',
      action: FilledButton(
        onPressed: () =>
            BackgroundSyncService.instance.requestIgnoreBatteryOptimizations(),
        child: const Text('Allow'),
      ),
      children: [if (forUnifiedPush) const _DistributorBatteryNote()],
    );
  }
}

class _DistributorBatteryNote extends StatelessWidget {
  const _DistributorBatteryNote();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: unifiedPushDeliveryProvider.distributorBatteryRestricted,
      builder: (context, restricted, _) {
        final distributor = unifiedPushDeliveryProvider.savedDistributor;
        if (!restricted || distributor == null) {
          return const SizedBox.shrink();
        }
        final name = unifiedPushDistributorDisplayName(distributor);
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$name delivers notifications to Zuno and is put to sleep too. '
                'Set its battery use to Unrestricted as well.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    BackgroundSyncService.instance.openAppSettings(distributor),
                child: Text('Open $name settings'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SecurityStep extends ConsumerWidget {
  final AccountSecurityStatus status;
  final Future<void> Function() onDone;

  const _SecurityStep({required this.status, required this.onDone});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (status == AccountSecurityStatus.noRecovery) {
      await ref.read(securityPromptStoreProvider).markPrompted();
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => status == AccountSecurityStatus.deviceLocked
            ? const ApproveThisDevicePage(showStartOver: true)
            : const SecureBackupPage(),
      ),
    );
    await onDone();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = accountSecurityCopy(status);
    return _StepScaffold(
      icon: status == AccountSecurityStatus.deviceLocked
          ? Icons.lock_outline
          : Icons.shield_outlined,
      title: copy.title,
      body: copy.body,
      action: FilledButton(
        onPressed: () => _open(context, ref),
        child: Text(copy.action ?? 'Open'),
      ),
    );
  }
}
