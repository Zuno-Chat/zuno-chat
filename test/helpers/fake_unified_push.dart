import 'package:unifiedpush_platform_interface/data/failed_reason.dart';
import 'package:unifiedpush_platform_interface/data/push_endpoint.dart';
import 'package:unifiedpush_platform_interface/data/push_message.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

class FakeUnifiedPush extends UnifiedPushPlatform {
  @override
  Future<List<String>> getDistributors(List<String> features) async => [];

  @override
  Future<String?> getDistributor() async => null;

  @override
  Future<void> saveDistributor(String distributor) async {}

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async {}

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async => false;

  @override
  Future<void> unregister(String instance) async {}

  @override
  Future<void> initializeCallback({
    void Function(PushEndpoint endpoint, String instance)? onNewEndpoint,
    void Function(FailedReason reason, String instance)? onRegistrationFailed,
    void Function(String instance)? onUnregistered,
    void Function(PushMessage message, String instance)? onMessage,
  }) async {}

  @override
  Future<void> initializeOnTempUnavailable(
    void Function(String instance)? onTempUnavailable,
  ) async {}

  @override
  void setLinuxOptions(LinuxOptions options) {}
}
