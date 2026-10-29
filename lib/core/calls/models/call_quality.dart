enum CallQuality {
  poor,
  degraded,
  good;

  CallQuality worse(CallQuality other) => other.index < index ? other : this;
}
