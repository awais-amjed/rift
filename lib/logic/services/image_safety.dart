/// The classifier's answer for one image, and the one question asked of it.
///
/// Three scores that sum to one, as `image-safety-classifier-xs` produces
/// them: safe, sexual, and gore. The decision is a single threshold on the
/// safe score rather than an argmax, because an image the model is only
/// half-sure is safe is exactly the image worth a blur.
class ImageSafetyVerdict {
  final double safe;
  final double sexual;
  final double gore;

  const ImageSafetyVerdict({
    required this.safe,
    required this.sexual,
    required this.gore,
  });

  /// Below this the image is covered. Deliberately above a coin flip: a
  /// classifier this small is wrong on a few percent of ordinary photographs,
  /// and covering the ones it merely doubts is the cheap direction to be
  /// wrong in — a tap costs a second, a picture shown by mistake cannot be
  /// unseen.
  static const double safeThreshold = 0.6;

  bool get isSensitive => safe < safeThreshold;

  /// Probabilities in the model's own class order: NSFL, NSFW, SFW.
  factory ImageSafetyVerdict.fromScores(List<double> scores) {
    if (scores.length != 3) {
      throw ArgumentError.value(scores, 'scores', 'expected three classes');
    }
    return ImageSafetyVerdict(
      gore: scores[0],
      sexual: scores[1],
      safe: scores[2],
    );
  }
}
