import 'package:unifiedpush_platform_interface/data/failed_reason.dart';
import 'package:unifiedpush_platform_interface/data/push_endpoint.dart';
import 'package:unifiedpush_platform_interface/data/push_message.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

class FakeUnifiedPush extends UnifiedPushPlatform {
  List<String> installed = const [];
  String? distributor;
  String? defaultDistributor;
  Object? unregisterError;
  final saved = <String>[];
  int lookups = 0;
  int distributorReads = 0;
  int registrations = 0;
  int unregistrations = 0;
  void Function(PushEndpoint endpoint, String instance)? onNewEndpoint;
  void Function(FailedReason reason, String instance)? onRegistrationFailed;

  @override
  Future<List<String>> getDistributors(List<String> features) async {
    lookups++;
    return installed;
  }

  @override
  Future<String?> getDistributor() async {
    distributorReads++;
    return distributor;
  }

  @override
  Future<void> saveDistributor(String distributor) async =>
      saved.add(distributor);

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async => registrations++;

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async {
    final chosen = defaultDistributor;
    if (chosen == null) return false;
    distributor = chosen;
    return true;
  }

  @override
  Future<void> unregister(String instance) async {
    unregistrations++;
    final error = unregisterError;
    if (error != null) throw error;
  }

  @override
  Future<void> initializeCallback({
    void Function(PushEndpoint endpoint, String instance)? onNewEndpoint,
    void Function(FailedReason reason, String instance)? onRegistrationFailed,
    void Function(String instance)? onUnregistered,
    void Function(PushMessage message, String instance)? onMessage,
  }) async {
    this.onNewEndpoint = onNewEndpoint;
    this.onRegistrationFailed = onRegistrationFailed;
  }

  @override
  Future<void> initializeOnTempUnavailable(
    void Function(String instance)? onTempUnavailable,
  ) async {}

  @override
  void setLinuxOptions(LinuxOptions options) {}
}
