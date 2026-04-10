/// Enumeration of picture types as defined by the FLAC specification
/// (derived from the ID3v2 APIC frame).
///
/// Each value has a numeric [code] that is stored in the [PictureBlock]
/// payload.
enum PictureType {
  /// Other picture type not covered by the remaining values.
  other(0),

  /// 32×32 pixel PNG file icon (mandatory format for type 1).
  fileIcon32x32(1),

  /// File icon other than a 32×32 PNG.
  otherFileIcon(2),

  /// Front cover image of the album or release.
  frontCover(3),

  /// Back cover image of the album or release.
  backCover(4),

  /// Leaflet page from the album packaging.
  leafletPage(5),

  /// Media surface (e.g. the label side of a CD).
  media(6),

  /// Lead artist or lead performer.
  leadArtist(7),

  /// Artist or performer.
  artist(8),

  /// Conductor.
  conductor(9),

  /// Band or orchestra.
  band(10),

  /// Composer.
  composer(11),

  /// Lyricist or text writer.
  lyricist(12),

  /// Recording location.
  recordingLocation(13),

  /// Photograph taken during recording.
  duringRecording(14),

  /// Photograph taken during performance.
  duringPerformance(15),

  /// Frame capture from a movie or video.
  movieScreenCapture(16),

  /// A bright, coloured fish (yes, really — inherited from ID3v2).
  brightColoredFish(17),

  /// Illustration related to the track or album.
  illustration(18),

  /// Band or artist logotype.
  bandLogo(19),

  /// Publisher or studio logotype.
  publisherLogo(20);

  /// Create a [PictureType] with the given numeric [code].
  const PictureType(this.code);

  /// The numeric code stored in the FLAC picture block payload.
  final int code;

  /// Return the [PictureType] corresponding to the given numeric [code].
  ///
  /// If [code] does not match any defined value, returns [other].
  static PictureType fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return PictureType.other;
  }
}
