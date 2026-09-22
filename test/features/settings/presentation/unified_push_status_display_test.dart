import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import 'package:zuno/features/settings/presentation/unified_push_status_display.dart';

void main() {
  group('unifiedPushStatusAction', () {
    test('offers Register once a distributor is picked', () {
      expect(
        unifiedPushStatusAction(UnifiedPushStatus.distributorSelected),
        UnifiedPushStatusAction.register,
      );
    });

    test('offers Retry after either kind of failure', () {
      expect(
        unifiedPushStatusAction(UnifiedPushStatus.registrationFailed),
        UnifiedPushStatusAction.retry,
      );
      expect(
        unifiedPushStatusAction(UnifiedPushStatus.pusherFailed),
        UnifiedPushStatusAction.retry,
      );
    });

    test('opens the details page only once actually registered', () {
      expect(
        unifiedPushStatusAction(UnifiedPushStatus.ready),
        UnifiedPushStatusAction.open,
      );
    });

    test('offers nothing while there is no distributor, or mid-flight', () {
      for (final status in [
        UnifiedPushStatus.idle,
        UnifiedPushStatus.noDistributorFound,
        UnifiedPushStatus.findingDistributor,
        UnifiedPushStatus.registering,
        UnifiedPushStatus.postingPusher,
      ]) {
        expect(
          unifiedPushStatusAction(status),
          UnifiedPushStatusAction.none,
          reason: '$status should offer no action',
        );
      }
    });
  });

  group('unifiedPushStatusLabel', () {
    test('says plain "Inactive" for every not-registered-yet state', () {
      for (final status in [
        UnifiedPushStatus.idle,
        UnifiedPushStatus.noDistributorFound,
      ]) {
        expect(unifiedPushStatusLabel(status), 'Inactive');
      }
    });

    test('never mentions distributors in any state', () {
      for (final status in UnifiedPushStatus.values) {
        expect(
          unifiedPushStatusLabel(status).toLowerCase(),
          isNot(contains('distributor app')),
          reason: '$status leaks distributor wording into the status row',
        );
      }
    });

    test('reports each failure distinctly', () {
      expect(
        unifiedPushStatusLabel(UnifiedPushStatus.registrationFailed),
        isNot(unifiedPushStatusLabel(UnifiedPushStatus.pusherFailed)),
      );
    });
  });

  group('unifiedPushDistributorLabel', () {
    test('shows the display name once one is picked', () {
      expect(
        unifiedPushDistributorLabel(
          status: UnifiedPushStatus.distributorSelected,
          distributor: 'io.heckel.ntfy',
        ),
        'ntfy',
      );
    });

    test('tells the user to install one when none are installed', () {
      expect(
        unifiedPushDistributorLabel(
          status: UnifiedPushStatus.noDistributorFound,
          distributor: '',
        ),
        contains('install'),
      );
    });

    test('distinguishes "still checking" from "checked, none picked"', () {
      expect(
        unifiedPushDistributorLabel(
          status: UnifiedPushStatus.idle,
          distributor: null,
        ),
        'Checking…',
      );
      expect(
        unifiedPushDistributorLabel(
          status: UnifiedPushStatus.idle,
          distributor: '',
        ),
        'None selected',
      );
    });
  });
}
