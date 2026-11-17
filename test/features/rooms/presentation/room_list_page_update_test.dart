import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/matrix/account/account_capabilities.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/security/security_prompt.dart';
import 'package:zuno/core/security/security_prompt_provider.dart';
import 'package:zuno/core/updates/find_update.dart';
import 'package:zuno/core/updates/update_checks.dart';
import 'package:zuno/core/updates/update_notice.dart';
import 'package:zuno/features/onboarding/presentation/onboarding_flow_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../../helpers/app_lifecycle.dart';
import '../../../helpers/fake_call_session.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_url_launcher.dart';
import '../../../helpers/room_list_page_harness.dart';

final _link = Uri.parse('https://zuno.chat/download');
AvailableUpdate _update(int build) => (build: build, link: _link);

void main() {
  late Client client;
  late List<String> launched;
  late Completer<AvailableUpdate?> answer;
  late SecurityPromptDecision prompt;

  setUp(() {
    client = buildTestClient(
      userId: '@me:example.org',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: FakeHttpClient((_) async => http.Response('{}', 200)),
    );
    prompt = SecurityPromptDecision.none;
  });

  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    AvailableUpdate? found,
    Future<List<OnboardingStep>> Function()? onboarding,
    Future<Object?> Function()? launchAnswer,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    launched = mockUrlLauncher(tester, answer: launchAnswer);
    answer = Completer();
    final container = await pumpRoomListPage(
      tester,
      client,
      overrides: [
        onboardingStepsProvider.overrideWith(
          (ref) => onboarding?.call() ?? Future.value(const []),
        ),
        securityPromptProvider.overrideWith((ref) async => prompt),
        accountCapabilitiesProvider.overrideWith(
          (ref) async => const AccountCapabilities(),
        ),
        updateChecksEnabledProvider.overrideWithValue(true),
        updateFinderProvider.overrideWithValue(() => answer.future),
      ],
    );
    await settle(tester);
    if (found != null) {
      answer.complete(found);
      await settle(tester);
    }
    return container;
  }

  Future<void> returnLater(WidgetTester tester) async {
    moveLifecycleTo(tester.binding, AppLifecycleState.paused);
    await withClock(
      Clock.fixed(clock.now().add(const Duration(hours: 7))),
      () async => moveLifecycleTo(tester.binding, AppLifecycleState.resumed),
    );
    await settle(tester);
  }

  Finder updateDialog([String version = '1.7.0']) => find.ancestor(
    of: find.textContaining(version),
    matching: find.byType(AlertDialog),
  );

  testWidgets('a found update is offered and Update opens where Zuno came '
      'from', (tester) async {
    await pumpHome(tester, found: _update(1007000));

    expect(find.text('Update available'), findsOneWidget);
    expect(updateDialog(), findsOneWidget);
    await tester.tap(find.text('Update'));
    await settle(tester);

    expect(launched, [_link.toString()]);
    expect(updateDialog(), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(updatesDismissedBuildKey), 1007000);
  });

  testWidgets('Not now keeps this version quiet after a return to the app', (
    tester,
  ) async {
    await pumpHome(tester, found: _update(1007000));
    await tester.tap(find.text('Not now'));
    await settle(tester);

    expect(launched, isEmpty);
    await returnLater(tester);
    expect(updateDialog(), findsNothing);
  });

  testWidgets('a newer version found on a later return is offered', (
    tester,
  ) async {
    await pumpHome(tester, found: _update(1007000));
    await tester.tap(find.text('Not now'));
    await settle(tester);

    answer = Completer()..complete(_update(1008000));
    await returnLater(tester);
    expect(updateDialog('1.8.0'), findsOneWidget);
  });

  testWidgets('an update found while another screen is open waits for home', (
    tester,
  ) async {
    await pumpHome(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other screen')),
        ),
      ),
    );
    await settle(tester);
    answer.complete(_update(1007000));
    await settle(tester);
    expect(updateDialog(), findsNothing);

    navigator.pop();
    await settle(tester);
    expect(updateDialog(), findsOneWidget);
  });

  testWidgets('an update found during a call waits for the call to end', (
    tester,
  ) async {
    final container = await pumpHome(tester);
    final calls = container.read(activeCallProvider.notifier);
    final room = buildTestRoom(client);
    calls.set(FakeCallSession(room: room, kind: CallKind.voice));
    answer.complete(_update(1007000));
    await settle(tester);
    expect(updateDialog(), findsNothing);

    calls.set(null);
    await settle(tester);
    expect(updateDialog(), findsOneWidget);
  });

  testWidgets('an update waits behind the recovery prompt', (tester) async {
    prompt = SecurityPromptDecision.setUpRecovery;
    await pumpHome(tester);
    expect(find.text('Set up recovery'), findsWidgets);
    answer.complete(_update(1007000));
    await settle(tester);
    expect(updateDialog(), findsNothing);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(updateDialog(), findsOneWidget);
  });

  testWidgets('the recovery prompt waits behind an update', (tester) async {
    final container = await pumpHome(tester, found: _update(1007000));
    expect(updateDialog(), findsOneWidget);

    prompt = SecurityPromptDecision.setUpRecovery;
    container.invalidate(securityPromptProvider);
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(updateDialog(), findsNothing);
    expect(find.text('Set up recovery'), findsWidgets);
  });

  testWidgets('an update found before onboarding is decided waits until '
      'onboarding is over', (tester) async {
    final steps = Completer<List<OnboardingStep>>();
    await pumpHome(tester, onboarding: () => steps.future);
    answer.complete(_update(1007000));
    await settle(tester);
    expect(updateDialog(), findsNothing);

    steps.complete(const [OnboardingStep.privacy]);
    await settle(tester);
    expect(find.byType(OnboardingFlowPage), findsOneWidget);
    expect(updateDialog(), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(updateDialog(), findsOneWidget);
  });

  testWidgets('an update link no app can open says so', (tester) async {
    await pumpHome(
      tester,
      found: _update(1007000),
      launchAnswer: () async => false,
    );
    await tester.tap(find.text('Update'));
    await settle(tester);

    expect(
      find.text('Link not opened. Visit zuno.chat/download in a browser.'),
      findsOneWidget,
    );
  });

  testWidgets('answering the popup after home has gone still remembers the '
      'version', (tester) async {
    await pumpHome(tester, found: _update(1007000));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.replace(
      oldRoute: ModalRoute.of(tester.element(find.byType(RoomListPage)))!,
      newRoute: MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await settle(tester);
    expect(find.byType(RoomListPage), findsNothing);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(updatesDismissedBuildKey), 1007000);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
