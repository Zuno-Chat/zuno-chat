class PreparedUiaPassword {
  String? _value;

  bool get isPrepared => _value != null;

  void prepare(String? password) {
    _value = (password == null || password.isEmpty) ? null : password;
  }

  String? take() {
    final value = _value;
    _value = null;
    return value;
  }

  void clear() => _value = null;
}
