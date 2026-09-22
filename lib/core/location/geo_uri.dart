class GeoUri {
  final double latitude;
  final double longitude;
  final double? uncertaintyMeters;

  const GeoUri({
    required this.latitude,
    required this.longitude,
    this.uncertaintyMeters,
  });

  static GeoUri? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (!trimmed.toLowerCase().startsWith('geo:')) return null;
    final parts = trimmed.substring(4).split(';');
    final coordinates = parts.first.split(',');
    if (coordinates.length < 2) return null;
    final latitude = double.tryParse(coordinates[0]);
    final longitude = double.tryParse(coordinates[1]);
    if (latitude == null || longitude == null) return null;
    if (!latitude.isFinite || !longitude.isFinite) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;

    double? uncertainty;
    for (final param in parts.skip(1)) {
      final separator = param.indexOf('=');
      if (separator < 0) continue;
      final key = param.substring(0, separator).toLowerCase();
      final value = param.substring(separator + 1);
      if (key == 'crs' && value.toLowerCase() != 'wgs84') return null;
      if (key == 'u') {
        final parsed = double.tryParse(value);
        if (parsed != null && parsed.isFinite && parsed >= 0) {
          uncertainty = parsed;
        }
      }
    }
    return GeoUri(
      latitude: latitude,
      longitude: longitude,
      uncertaintyMeters: uncertainty,
    );
  }

  String toUriString() {
    final base = 'geo:${_compact(latitude)},${_compact(longitude)}';
    final u = uncertaintyMeters;
    return u == null ? base : '$base;u=${_compact(u)}';
  }

  String get coordinatesLabel =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  Uri get externalMapsUri {
    final point = '${_compact(latitude)},${_compact(longitude)}';
    return Uri.parse('geo:$point?q=$point');
  }

  static String _compact(double value) =>
      value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  bool operator ==(Object other) =>
      other is GeoUri &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.uncertaintyMeters == uncertaintyMeters;

  @override
  int get hashCode => Object.hash(latitude, longitude, uncertaintyMeters);

  @override
  String toString() => toUriString();
}
