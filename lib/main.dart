import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'models/reading_settings.dart';
import 'screens/home_screen.dart';
import 'services/reading_settings_service.dart';
import 'ui/app_visuals.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint('======== FLUTTER ERROR ========');
    debugPrint(details.exceptionAsString());
    debugPrint(details.stack?.toString());
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('======== PLATFORM ERROR ========');
    debugPrint(error.toString());
    debugPrint(stack.toString());
    return true;
  };

  runApp(const NaloriApp());
}

class NaloriApp extends StatefulWidget {
  const NaloriApp({super.key});

  @override
  State<NaloriApp> createState() => _NaloriAppState();
}

class _NaloriAppState extends State<NaloriApp> {
  final _settingsService = ReadingSettingsService();

  @override
  void initState() {
    super.initState();
    _settingsService.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadingSettings>(
      valueListenable: ReadingSettingsService.settingsNotifier,
      builder: (context, settings, _) {
        final followsSystemTheme = settings.appTheme == AppTheme.system;
        return MaterialApp(
          title: 'Nalori',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          themeMode: followsSystemTheme ? ThemeMode.system : ThemeMode.dark,
          theme: AppUi.appTheme(
            settings.copyWith(
              appTheme: AppTheme.softLight,
              clearReaderTheme: true,
            ),
          ),
          darkTheme: AppUi.appTheme(
            followsSystemTheme
                ? settings.copyWith(
                    appTheme: AppTheme.dark,
                    clearReaderTheme: true,
                  )
                : settings.copyWith(clearReaderTheme: true),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}
