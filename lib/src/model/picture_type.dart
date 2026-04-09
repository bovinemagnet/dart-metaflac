enum PictureType {
  other(0),
  fileIcon32x32(1),
  otherFileIcon(2),
  frontCover(3),
  backCover(4),
  leafletPage(5),
  media(6),
  leadArtist(7),
  artist(8),
  conductor(9),
  band(10),
  composer(11),
  lyricist(12),
  recordingLocation(13),
  duringRecording(14),
  duringPerformance(15),
  movieScreenCapture(16),
  brightColoredFish(17),
  illustration(18),
  bandLogo(19),
  publisherLogo(20);

  const PictureType(this.code);
  final int code;

  static PictureType fromCode(int code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return PictureType.other;
  }
}
