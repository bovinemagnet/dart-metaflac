/// Base exception for all FLAC metadata operations.
///
/// All exceptions thrown by this library extend this class, allowing
/// callers to catch any FLAC-related error with a single type.
class FlacMetadataException implements Exception {
  /// Create a [FlacMetadataException] with the given [message] and optional
  /// [cause].
  FlacMetadataException(this.message, {this.cause});

  /// Human-readable description of the error.
  final String message;

  /// The underlying cause of this exception, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when input bytes do not represent a valid FLAC file.
///
/// This includes missing or corrupt `fLaC` stream markers, invalid header
/// fields, or structurally broken metadata block chains.
class InvalidFlacException extends FlacMetadataException {
  /// Create an [InvalidFlacException] with the given [message] and optional
  /// [cause].
  InvalidFlacException(super.message, {super.cause});
}

/// Thrown when a metadata block's internal structure is malformed.
///
/// The FLAC stream marker may be valid, but one or more metadata blocks
/// contain data that cannot be parsed according to the FLAC specification.
class MalformedMetadataException extends FlacMetadataException {
  /// Create a [MalformedMetadataException] with the given [message] and
  /// optional [cause].
  MalformedMetadataException(super.message, {super.cause});
}

/// Thrown when an operation encounters a metadata block type it cannot handle.
///
/// This may occur when attempting to interpret a reserved or future block
/// type that the library does not yet support.
class UnsupportedBlockException extends FlacMetadataException {
  /// Create an [UnsupportedBlockException] with the given [message] and
  /// optional [cause].
  UnsupportedBlockException(super.message, {super.cause});
}

/// Thrown when an in-place metadata update cannot fit within the available
/// padding.
///
/// This indicates that a full rewrite of the FLAC file is required because
/// the updated metadata is larger than the existing metadata region
/// (including padding).
class FlacInsufficientPaddingException extends FlacMetadataException {
  /// Create a [FlacInsufficientPaddingException] with the given [message]
  /// and optional [cause].
  FlacInsufficientPaddingException(super.message, {super.cause});
}

/// Thrown when a write operation detects a conflict, such as the source
/// file having been modified since it was read.
class WriteConflictException extends FlacMetadataException {
  /// Create a [WriteConflictException] with the given [message] and optional
  /// [cause].
  WriteConflictException(super.message, {super.cause});
}

/// Thrown when a file I/O operation fails during FLAC read or write.
///
/// Wraps underlying filesystem errors encountered by the I/O layer.
class FlacIoException extends FlacMetadataException {
  /// Create a [FlacIoException] with the given [message] and optional
  /// [cause].
  FlacIoException(super.message, {super.cause});
}

/// Backward-compatible alias for [InvalidFlacException].
class FlacCorruptHeaderException extends InvalidFlacException {
  /// Create a [FlacCorruptHeaderException] with the given [message] and
  /// optional [cause].
  FlacCorruptHeaderException(super.message, {super.cause});
}
