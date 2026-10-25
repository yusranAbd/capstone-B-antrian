/// Reuse a small set of decode sizes across list/header avatars and DPR values.
/// Native codecs can avoid allocating a full-resolution thumbnail. Web engines
/// may ignore decode hints, so this is not a claim about browser process RAM.
int imageDecodeWidth(double logicalWidth, double devicePixelRatio) {
  final target = (logicalWidth * devicePixelRatio).ceil();
  return const [
    64,
    128,
    256,
    512,
    1024,
  ].firstWhere((size) => size >= target, orElse: () => target);
}
