bool shouldReturnToRootRoute({required bool? previous, required bool? next}) {
  if (next != false) return false;
  return previous == true;
}
