enum WriteMode { safeAtomic, auto, inPlaceIfPossible, outputToNewFile }

final class FlacTransformOptions {
  const FlacTransformOptions({
    this.writeMode = WriteMode.safeAtomic,
    this.explicitPaddingSize,
  });
  final WriteMode writeMode;
  final int? explicitPaddingSize;
  static const FlacTransformOptions defaults = FlacTransformOptions();
}
