class FlacCorruptHeaderException implements Exception {
  final String message;
  const FlacCorruptHeaderException(this.message);
  @override
  String toString() => 'FlacCorruptHeaderException: $message';
}

class FlacInsufficientPaddingException implements Exception {
  final String message;
  const FlacInsufficientPaddingException(this.message);
  @override
  String toString() => 'FlacInsufficientPaddingException: $message';
}
