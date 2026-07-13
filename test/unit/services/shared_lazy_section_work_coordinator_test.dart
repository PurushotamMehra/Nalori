import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/models/book_chunk.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';

void main() {
  test('different priorities join and promote one queued job', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final identity = _identity();
    var invocations = 0;
    final first = coordinator.request(
      identity: identity,
      owner: Object(),
      priority: LazySectionWorkPriority.parsedHydration,
      operation: () async {
        invocations++;
        return _section(identity);
      },
    );
    final second = coordinator.request(
      identity: identity,
      owner: Object(),
      priority: LazySectionWorkPriority.explicitNavigation,
      operation: () async => throw StateError('must join'),
    );

    expect(second.future, same(first.future));
    expect(
      coordinator.priorityFor(identity),
      LazySectionWorkPriority.explicitNavigation,
    );
    await Future.wait([first.future, second.future]);
    expect(invocations, 1);
  });

  test('different section identities do not join', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final firstIdentity = _identity();
    final secondIdentity = _identity(spineIndex: 2, href: 'text/two.xhtml');
    var invocations = 0;

    final results = await Future.wait([
      coordinator
          .request(
            identity: firstIdentity,
            owner: Object(),
            priority: LazySectionWorkPriority.explicitNavigation,
            operation: () async {
              invocations++;
              return _section(firstIdentity);
            },
          )
          .future,
      coordinator
          .request(
            identity: secondIdentity,
            owner: Object(),
            priority: LazySectionWorkPriority.explicitNavigation,
            operation: () async {
              invocations++;
              return _section(secondIdentity);
            },
          )
          .future,
    ]);

    expect(results, hasLength(2));
    expect(invocations, 2);
  });

  test('publication fingerprint changes do not join', () async {
    await _expectDistinctJobs(
      _identity(publicationFingerprint: 'publication-a'),
      _identity(publicationFingerprint: 'publication-b'),
    );
  });

  test('parser version and checksum changes do not join', () async {
    await _expectDistinctJobs(
      _identity(parserVersion: 'parser-a'),
      _identity(parserVersion: 'parser-b'),
    );
    await _expectDistinctJobs(
      _identity(sourceChecksum: 'checksum-a'),
      _identity(sourceChecksum: 'checksum-b'),
    );
  });

  test('one owner leaving does not cancel another owner', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final identity = _identity();
    final firstOwner = Object();
    final secondOwner = Object();
    final gate = Completer<void>();
    var invocations = 0;
    final first = coordinator.request(
      identity: identity,
      owner: firstOwner,
      priority: LazySectionWorkPriority.explicitNavigation,
      operation: () async {
        invocations++;
        await gate.future;
        return _section(identity);
      },
    );
    final second = coordinator.request(
      identity: identity,
      owner: secondOwner,
      priority: LazySectionWorkPriority.visibleSection,
      operation: () async => throw StateError('must join'),
    );
    coordinator.releaseOwner(firstOwner);
    gate.complete();

    expect(await second.future, same(await first.future));
    expect(invocations, 1);
  });

  test('all owners leaving cancels queued speculative work', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final identity = _identity();
    final owner = Object();
    var invocations = 0;
    final request = coordinator.request(
      identity: identity,
      owner: owner,
      priority: LazySectionWorkPriority.parsedHydration,
      operation: () async {
        invocations++;
        return _section(identity);
      },
    );

    coordinator.releaseOwner(owner);

    await expectLater(
      request.future,
      throwsA(isA<SharedSectionWorkCancelled>()),
    );
    expect(invocations, 0);
    expect(coordinator.activeJobCount, 0);
  });

  test('failure removes the shared entry and permits retry', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final identity = _identity();
    var invocations = 0;
    final failed = coordinator.request(
      identity: identity,
      owner: Object(),
      priority: LazySectionWorkPriority.explicitNavigation,
      operation: () async {
        invocations++;
        throw StateError('parse failed');
      },
    );
    await expectLater(failed.future, throwsStateError);

    final retried = coordinator.request(
      identity: identity,
      owner: Object(),
      priority: LazySectionWorkPriority.explicitNavigation,
      operation: () async {
        invocations++;
        return _section(identity);
      },
    );
    expect(await retried.future, isA<ParsedSection>());
    expect(invocations, 2);
  });

  test('immediate close and reopen joins launched reusable work', () async {
    final coordinator = SharedLazySectionWorkCoordinator();
    final identity = _identity();
    final closingOwner = Object();
    final reopeningOwner = Object();
    final launched = Completer<void>();
    final gate = Completer<void>();
    var invocations = 0;
    final closing = coordinator.request(
      identity: identity,
      owner: closingOwner,
      priority: LazySectionWorkPriority.explicitNavigation,
      operation: () async {
        invocations++;
        launched.complete();
        await gate.future;
        return _section(identity);
      },
    );
    await launched.future;
    coordinator.releaseOwner(closingOwner);

    final reopened = coordinator.request(
      identity: identity,
      owner: reopeningOwner,
      priority: LazySectionWorkPriority.visibleSection,
      operation: () async => throw StateError('must join'),
    );
    gate.complete();

    expect(reopened.future, same(closing.future));
    await reopened.future;
    expect(invocations, 1);
  });
}

Future<void> _expectDistinctJobs(
  LazySectionIdentity first,
  LazySectionIdentity second,
) async {
  final coordinator = SharedLazySectionWorkCoordinator();
  var invocations = 0;
  await Future.wait([
    coordinator
        .request(
          identity: first,
          owner: Object(),
          priority: LazySectionWorkPriority.explicitNavigation,
          operation: () async {
            invocations++;
            return _section(first);
          },
        )
        .future,
    coordinator
        .request(
          identity: second,
          owner: Object(),
          priority: LazySectionWorkPriority.explicitNavigation,
          operation: () async {
            invocations++;
            return _section(second);
          },
        )
        .future,
  ]);
  expect(invocations, 2);
}

LazySectionIdentity _identity({
  int spineIndex = 1,
  String href = 'text/one.xhtml',
  String publicationFingerprint = 'publication-v1',
  String sourceChecksum = 'checksum-v1',
  String parserVersion = lazyParsedSectionParserVersion,
  String dependencySignature = 'dependencies-v1',
}) {
  return LazySectionIdentity(
    bookId: 'book.epub',
    publicationFingerprint: publicationFingerprint,
    spineIndex: spineIndex,
    href: href,
    normalizedHref: href,
    fullPath: 'OEBPS/$href',
    sourceChecksum: sourceChecksum,
    parserVersion: parserVersion,
    dependencySignature: dependencySignature,
    dependencySchemaVersion: lazyParsedSectionDependencySchemaVersion,
  );
}

ParsedSection _section(LazySectionIdentity identity) {
  return ParsedSection(
    identity: identity,
    chunks: const [
      BookChunk(index: 0, type: BookChunkType.text, text: 'section'),
    ],
    anchorMap: const {},
    chapters: const [],
    wordCount: 1,
    textCharCount: 7,
    resourceHrefs: const [],
    parserVersion: identity.parserVersion,
  );
}
