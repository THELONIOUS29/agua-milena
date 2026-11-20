import 'package:intl/intl.dart';

class CurrencyUtils {
  CurrencyUtils._();

  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_EC',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final NumberFormat _compactFormat = NumberFormat.compactCurrency(
    locale: 'es_EC',
    symbol: '\$',
    decimalDigits: 2,
  );

  static String format(double amount) => _currencyFormat.format(amount);
  static String formatCompact(double amount) => _compactFormat.format(amount);

  static String formatChange(double amount) {
    final formatted = format(amount.abs());
    return amount >= 0 ? '+$formatted' : '-$formatted';
  }
}
