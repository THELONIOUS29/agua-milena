import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  // Sin locale 'es' para evitar LocaleDataException en static final lazy init.
  // El formato dd/MM/yyyy es independiente del locale.
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _dayMonthFormat = DateFormat('dd MMM');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');

  static String formatDate(DateTime date) => _dateFormat.format(date);
  static String formatDateTime(DateTime date) => _dateTimeFormat.format(date);
  static String formatTime(DateTime date) => _timeFormat.format(date);
  static String formatDayMonth(DateTime date) => _dayMonthFormat.format(date);
  static String formatMonthYear(DateTime date) => _monthYearFormat.format(date);

  static String weekdayInitial(DateTime date) {
    const labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return labels[date.weekday - DateTime.monday];
  }

  static String formatRelative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Hoy';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return formatDate(date);
  }

  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  static List<DateTime> lastNDays(int n) {
    final today = DateTime.now();
    return List.generate(n, (i) => today.subtract(Duration(days: n - 1 - i)));
  }
}
