const scheduleDays = [
  'SENIN',
  'SELASA',
  'RABU',
  'KAMIS',
  'JUMAT',
  'SABTU',
  'MINGGU',
];

enum ScheduleOutcome { created, existing, failed, uncertain }

class ScheduleResult {
  const ScheduleResult(this.day, this.outcome, this.message);
  final String day, message;
  final ScheduleOutcome outcome;
}
