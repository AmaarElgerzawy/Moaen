import 'package:intl/intl.dart';

/// Formats dates and times the way the design writes them.
///
/// Every one of these exists because the obvious `DateFormat(..., 'ar')` produces
/// Arabic-Indic digits — `١٠:٠٠ ص` where the design writes `10:00 ص`. The two are
/// not interchangeable: the design's phone numbers, prices, odometer readings and
/// report numbers all use Western digits, and a time is a number like any other
/// in a document that mixes them. Writing the format out of Arabic *month and
/// weekday names* with Western digits is what keeps the two conventions in the
/// same document instead of in different ones.
///
/// The locale is passed in rather than read from a global, so a widget test can
/// ask for the Arabic formatting without a `Localizations` ancestor.
class SaudiFormat {
  const SaudiFormat(this.localeName);

  final String localeName;

  /// `الأحد`, the weekday alone.
  String weekday(DateTime when) => DateFormat('EEEE', localeName).format(when);

  /// `19 سبتمبر 2026` — day, Arabic month name, year.
  ///
  /// Assembled from parts rather than `DateFormat('d MMMM yyyy', localeName)`,
  /// because the pattern form would take the digits from the locale too.
  String longDate(DateTime when) =>
      '${when.day} ${DateFormat('MMMM', localeName).format(when)} ${when.year}';

  /// `10:00 ص` — 12-hour clock, Western digits, the locale's own meridiem.
  ///
  /// The meridiem comes from the locale while the digits do not, which is why the
  /// two formatters are mixed: `h:mm a` would give `١٠:٠٠ ص` and `h:mm` alone
  /// would give no meridiem at all.
  String time(DateTime when) {
    final String clock = DateFormat('h:mm', 'en').format(when);
    return '$clock ${_meridiem(when)}';
  }

  /// `10:00` with no meridiem, for a field where the design shows the period in a
  /// neighbouring field.
  String clock(DateTime when) => DateFormat('h:mm', 'en').format(when);

  /// `10:00 صباحاً` — the long meridiem, as the buyer's appointment notice writes
  /// it. The step timeline uses [time] and its short `ص`; the notice uses this
  /// and its `صباحاً`. The design uses both on the same screen, and collapsing
  /// them would change the reference rather than simplify it.
  String timeLong(DateTime when) =>
      '${DateFormat('h:mm', 'en').format(when)} ${longMeridiem(when)}';

  /// `صباحاً` or `مساءً`, for the design's `صباحاً 10:00` booking field.
  String longMeridiem(DateTime when) => when.hour < 12 ? 'صباحاً' : 'مساءً';

  String _meridiem(DateTime when) => when.hour < 12 ? 'ص' : 'م';

  /// A relative time for the job board: `منذ 5 دقائق`, `منذ 18 دقيقة`,
  /// `منذ ساعتين`, `منذ 3 أيام`.
  ///
  /// The singular/plural agreement is the point of this method. Arabic has three
  /// forms where English has two — one, two, and three-or-more — and the design
  /// writes `منذ 5 دقائق` next to `منذ 18 دقيقة` to show that the form follows
  /// the number. `timeMinutesAgo` in the ARB carries that as an ICU plural, so
  /// the two ends are built from the same vocabulary and cannot drift.
  ///
  /// A future timestamp — a clock skew between the phone and the server, which is
  /// ordinary — reads as "just now" rather than a negative age.
  String relative(DateTime when, DateTime now) {
    final Duration age = now.difference(when);
    if (age.isNegative || age.inMinutes < 1) return 'منذ لحظات';
    if (age.inMinutes < 60) return _plural(age.inMinutes, 'دقيقة', 'دقيقتين', 'دقائق');
    if (age.inHours < 24) return _plural(age.inHours, 'ساعة', 'ساعتين', 'ساعات');
    return _plural(age.inDays, 'يوم', 'يومين', 'أيام');
  }

  /// Arabic's three-form count: exactly one, exactly two, and everything else.
  String _plural(int count, String one, String two, String many) {
    if (count == 1) return 'منذ $one';
    if (count == 2) return 'منذ $two';
    return 'منذ $count $many';
  }
}
