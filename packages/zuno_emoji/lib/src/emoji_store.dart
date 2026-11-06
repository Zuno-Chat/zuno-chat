abstract interface class EmojiStore {
  String? read(String key);

  Future<void> write(String key, String value);
}
