import 'package:flutter/widgets.dart';
import 'package:shop/l10n/strings_en.dart';
import 'package:shop/l10n/strings_te.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return value!;
  }

  static const supportedLocales = <Locale>[Locale('en'), Locale('te')];

  String t(String key) {
    final languageCode = locale.languageCode.toLowerCase();
    if (languageCode == 'te') {
      return stringsTe[key] ?? stringsEn[key] ?? key;
    }
    return stringsEn[key] ?? key;
  }

  /// Translates bundled catalogue labels without changing shop-defined names.
  String catalog(String value) {
    if (locale.languageCode.toLowerCase() == 'te') {
      return catalogTe[value] ?? value;
    }
    return value;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}
