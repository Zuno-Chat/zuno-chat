import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OnboardingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = OnboardingStore(await SharedPreferences.getInstance());
  });

  test('nothing has been asked yet on a fresh install', () {
    expect(store.shown('@alex:example.org'), isEmpty);
    expect(store.flowInProgress, isFalse);
  });

  test('no account counts as just registered on a fresh install', () {
    expect(store.justRegistered('@alex:example.org'), isFalse);
  });

  test('registering is remembered until the profile step is shown', () async {
    await store.markRegistered('@alex:example.org');

    expect(store.justRegistered('@alex:example.org'), isTrue);
    expect(store.justRegistered('@bea:example.org'), isFalse);
  });

  test('registering survives a new store on the same preferences', () async {
    await store.markRegistered('@alex:example.org');
    final reopened = OnboardingStore(await SharedPreferences.getInstance());

    expect(reopened.justRegistered('@alex:example.org'), isTrue);
  });

  test('a step marked shown stays shown', () async {
    await store.markShown('@alex:example.org', OnboardingStep.profile);

    expect(store.shown('@alex:example.org'), {OnboardingStep.profile});
  });

  test('marking is additive rather than replacing', () async {
    await store.markShown('@alex:example.org', OnboardingStep.profile);
    await store.markShown('@alex:example.org', OnboardingStep.notifications);

    expect(store.shown('@alex:example.org'), {
      OnboardingStep.profile,
      OnboardingStep.notifications,
    });
  });

  test('marking the same step twice is not an error', () async {
    await store.markShown('@alex:example.org', OnboardingStep.profile);
    await store.markShown('@alex:example.org', OnboardingStep.profile);

    expect(store.shown('@alex:example.org'), {OnboardingStep.profile});
  });

  test('another account on the same phone starts from nothing', () async {
    await store.markShown('@alex:example.org', OnboardingStep.profile);

    expect(store.shown('@sam:example.org'), isEmpty);
  });

  test('a stored value from a removed step is ignored, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding.shown.@alex:example.org': ['profile', 'chooseDistributor'],
    });
    store = OnboardingStore(await SharedPreferences.getInstance());

    expect(store.shown('@alex:example.org'), {OnboardingStep.profile});
  });
}
