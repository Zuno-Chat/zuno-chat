import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/navigation/root_route_reset.dart';

void main() {
  test('clears the stack when a logged-in session ends', () {
    expect(shouldReturnToRootRoute(previous: true, next: false), isTrue);
  });

  test('leaves the auth flow alone on a cold start', () {
    expect(shouldReturnToRootRoute(previous: null, next: false), isFalse);
  });

  test('leaves a half-typed login form alone when logged-out repeats', () {
    expect(shouldReturnToRootRoute(previous: false, next: false), isFalse);
  });

  test('does nothing on the way in', () {
    expect(shouldReturnToRootRoute(previous: false, next: true), isFalse);
    expect(shouldReturnToRootRoute(previous: null, next: true), isFalse);
  });

  test('waits rather than acting while the state is unknown', () {
    expect(shouldReturnToRootRoute(previous: true, next: null), isFalse);
  });
}
