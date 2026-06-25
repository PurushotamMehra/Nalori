import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'models/book_metadata.dart';
import 'models/reading_settings.dart';
import 'screens/home_screen.dart';
import 'screens/reader_screen.dart';
import 'services/book_metadata_service.dart';
import 'services/reading_settings_service.dart';
import 'ui/app_visuals.dart';

const String _diagReaderBookPath = String.fromEnvironment(
  'NALORI_READER_DIAG_BOOK_PATH',
);

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
          home: _diagReaderBookPath.isEmpty
              ? const HomeScreen()
              : _DiagReaderLauncher(
                  path: _diagReaderBookPath,
                  settings: settings,
                ),
        );
      },
    );
  }
}

class _DiagReaderLauncher extends StatelessWidget {
  const _DiagReaderLauncher({required this.path, required this.settings});

  final String path;
  final ReadingSettings settings;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DiagReaderLaunchData>(
      future: _resolveDiagReaderLaunchData(path),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ReaderScreen.directContinue(
          bookFile: data.file,
          metadata: data.metadata,
          settings: settings,
        );
      },
    );
  }
}

class _DiagReaderLaunchData {
  const _DiagReaderLaunchData({required this.file, required this.metadata});

  final File file;
  final BookMetadata metadata;
}

Future<_DiagReaderLaunchData> _resolveDiagReaderLaunchData(String path) async {
  final file = await _resolveDiagBookFile(path);
  final bookId = file.path.split(Platform.pathSeparator).last;
  final metadataService = BookMetadataService();
  await metadataService.init();
  final saved = metadataService.getMetadata(bookId);
  final metadata =
      saved?.copyWith(managedFilePath: file.path) ??
      BookMetadata(
        id: bookId,
        managedFilePath: file.path,
        title: 'Nalori Diagnostics',
        author: 'Diagnostics',
      );
  if (saved == null || saved.managedFilePath != file.path) {
    await metadataService.updateMetadata(metadata);
  }
  return _DiagReaderLaunchData(file: file, metadata: metadata);
}

Future<File> _resolveDiagBookFile(String path) async {
  if (!path.startsWith('asset:')) return File(path);
  final assetPath = path.substring('asset:'.length);
  final bytes = await rootBundle.load(assetPath);
  final fileName = assetPath.split('/').last;
  final file = File('${Directory.systemTemp.path}/$fileName');
  await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  return file;
}
