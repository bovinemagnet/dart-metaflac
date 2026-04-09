final class FlacBlockHeader {
  const FlacBlockHeader({
    required this.isLast,
    required this.typeCode,
    required this.payloadLength,
  });
  final bool isLast;
  final int typeCode;
  final int payloadLength;
}
