import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/library_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory booksDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nalori_library_service_');
    booksDir = Directory(p.join(tempDir.path, 'books'));
    await booksDir.create(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolves exact managed EPUB path without listing library', () async {
    final nested = Directory(p.join(tempDir.path, 'renamed'));
    await nested.create();
    final exact = File(p.join(nested.path, 'custom.epub'));
    await exact.writeAsString('epub bytes', flush: true);
    final legacy = File(p.join(booksDir.path, 'book.epub'));
    await legacy.writeAsString('legacy bytes', flush: true);

    final result = await LibraryService().localBookForMetadata(
      bookId: 'book.epub',
      managedFilePath: exact.path,
    );

    expect(result?.path, exact.path);
  });

  test('falls back to deterministic legacy managed path', () async {
    final legacy = File(p.join(booksDir.path, 'legacy.epub'));
    await legacy.writeAsString('legacy bytes', flush: true);

    final result = await LibraryService().localBookForMetadata(
      bookId: 'legacy.epub',
      managedFilePath: p.join(tempDir.path, 'missing.epub'),
    );

    expect(result?.path, legacy.path);
  });

  test('returns null for missing or empty EPUB paths', () async {
    final empty = File(p.join(booksDir.path, 'empty.epub'));
    await empty.writeAsBytes(const [], flush: true);

    final result = await LibraryService().localBookForMetadata(
      bookId: 'empty.epub',
      managedFilePath: p.join(tempDir.path, 'missing.epub'),
    );

    expect(result, isNull);
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
