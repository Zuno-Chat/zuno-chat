class RingingCall {
  RingingCall._();
  static final instance = RingingCall._();

  String? callId;

  void set(String callId) => this.callId = callId;

  void clear(String callId) {
    if (this.callId == callId) this.callId = null;
  }
}
