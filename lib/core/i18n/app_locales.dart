import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Localization wiring for `GetMaterialApp`, kept in one place so adding a
/// language is a change here plus translations, not a hunt through main.dart.
///
/// Only English is listed: every app string is still an English literal in
/// its widget, so declaring e.g. Swahili now would give Swahili Material
/// chrome (date pickers, tooltips) around English screens. Extracting
/// strings into ARB files (`flutter gen-l10n`) is the next step before
/// another locale belongs here.
class AppLocales {
  AppLocales._();

  static const supported = [Locale('en')];

  static const delegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}
