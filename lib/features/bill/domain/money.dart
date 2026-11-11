/// Reading and writing money.
///
/// Spec: VENUES.md §15. Amounts are integer **minor units** everywhere —
/// paise, cents — because `0.1 + 0.2` is not `0.3` and a split that quietly
/// loses a rupee is the kind of thing six people notice while staring at a
/// bill. The only division by 100 in the app happens at the last moment, for
/// display.
library;

import 'package:intl/intl.dart';

/// Read what someone typed into the amount field.
///
/// Returns null when it is not a number, so the field can stay empty and
/// unvalidated until there is something to validate. Deliberately forgiving:
/// people type "₹2,400", "2400.50" and "2,400 " at a restaurant table, and
/// none of those should be an error.
int? parseMinor(String input) {
  // Strip anything that is not a digit or a decimal point: currency symbols,
  // thousands separators, stray spaces.
  final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;

  final parts = cleaned.split('.');
  // "1.2.3" is not a number, however generous we are feeling.
  if (parts.length > 2) return null;

  final whole = parts[0].isEmpty ? '0' : parts[0];
  final major = int.tryParse(whole);
  if (major == null) return null;

  if (parts.length == 1) return major * 100;

  // Pad "2400.5" to 50 paise, truncate "2400.567" to 56 — never round up into
  // money the table did not agree to.
  final frac = parts[1].padRight(2, '0').substring(0, 2);
  final minor = int.tryParse(frac);
  if (minor == null) return null;

  return major * 100 + minor;
}

/// Format minor units for display.
///
/// [localeName] is injectable so tests are not at the mercy of the machine
/// they run on. Falls back to Indian formatting, which is the launch market
/// and the only place where the grouping differs enough to matter —
/// ₹2,40,000 rather than ₹240,000.
String formatMoney(int minor, {String localeName = 'en_IN', String? symbol}) {
  final whole = minor % 100 == 0;
  // Hide ".00" on a round number. Nobody writes ₹600.00 on a napkin.
  final digits = whole ? 0 : 2;
  try {
    // `simpleCurrency` rather than `currency`: the latter prints the ISO code
    // — "INR600" — unless handed an explicit symbol, which is not what anyone
    // wants to read while splitting a bill.
    final format = symbol == null
        ? NumberFormat.simpleCurrency(
            locale: localeName,
            decimalDigits: digits,
          )
        : NumberFormat.currency(
            locale: localeName,
            symbol: symbol,
            decimalDigits: digits,
          );
    return format.format(minor / 100);
  } catch (_) {
    // An unknown locale must not take the split screen down with it.
    final major = minor ~/ 100;
    final paise = (minor % 100).toString().padLeft(2, '0');
    return whole ? '${symbol ?? ''}$major' : '${symbol ?? ''}$major.$paise';
  }
}
