class FlacMetadataException implements Exception {
  FlacMetadataException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => '$runtimeType: $message';
}

class InvalidFlacException extends FlacMetadataException {
  InvalidFlacException(super.message, {super.cause});
}

class MalformedMetadataException extends FlacMetadataException {
  MalformedMetadataException(super.message, {super.cause});
}

class UnsupportedBlockException extends FlacMetadataException {
  UnsupportedBlockException(super.message, {super.cause});
}

class FlacInsufficientPaddingException extends FlacMetadataException {
  FlacInsufficientPaddingException(super.message, {super.cause});
}

class WriteConflictException extends FlacMetadataException {
  WriteConflictException(super.message, {super.cause});
}

class FlacIoException extends FlacMetadataException {
  FlacIoException(super.message, {super.cause});
}

/// Backward-compatible alias for [InvalidFlacException].
class FlacCorruptHeaderException extends InvalidFlacException {
  FlacCorruptHeaderException(super.message, {super.cause});
}
