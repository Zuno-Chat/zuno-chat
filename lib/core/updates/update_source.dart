enum UpdateSource { play, appStore, website }

UpdateSource? updateSourceFor(
  String? installerStore,
  Set<UpdateSource> offered,
) {
  final store = switch (installerStore) {
    'com.android.vending' => UpdateSource.play,
    'com.apple' => UpdateSource.appStore,
    _ => null,
  };
  if (store != null && offered.contains(store)) return store;
  return offered.contains(UpdateSource.website) ? UpdateSource.website : null;
}
