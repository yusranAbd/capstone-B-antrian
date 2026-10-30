import 'queueb_motion.dart';

/// Compatibility names preserve the verified patient pilot API and behavior.
class PatientMotionOnce extends QueueBMotionOnce {}

class PatientMicroEntrance extends QueueBMicroEntrance {
  const PatientMicroEntrance({
    super.key,
    required super.once,
    required super.child,
  });

  static const duration = QueueBMotion.standard;
  static const minimumOpacity = QueueBMotion.minimumOpacity;
}
