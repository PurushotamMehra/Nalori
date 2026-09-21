import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nalori/services/epub_parser.dart';
import 'package:nalori/services/lazy_book_session.dart';
import 'package:nalori/services/lazy_parsed_book.dart';
import 'package:nalori/services/lazy_section_repository.dart';
import 'package:nalori/services/parsed_section_cache_service.dart';

import 'support/lazy_address_fixture.dart';

// Service-path evidence only. No simulated visible publication/coordinator.
void main() {
  late Directory root;
  late File epub;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lazy-direct-proof-');
    epub = await File(
      '${root.path}/direct.epub',
    ).writeAsBytes(buildAddressFixture());
  });
  tearDown(() => root.delete(recursive: true));

  for (final holdWarmup in [false, true]) {
    test(
      holdWarmup
          ? 'D02 RED direct demand must preempt held speculative parser'
          : 'D01 CONTROL chapter 1 to 6 parses no intermediate chapters',
      () async {
        final starts = <int>[];
        final entered = Completer<void>();
        final release = Completer<void>();
        final coordinator = SharedLazySectionWorkCoordinator();
        final session = LazyBookSession(
          repository: LazySectionRepository(
            cache: ParsedSectionCacheService(
              rootDirectory: Directory('${root.path}/cache'),
            ),
            workCoordinator: coordinator,
            parser: (request) async {
              starts.add(request.identity.spineIndex);
              if (holdWarmup && request.identity.spineIndex == 6) {
                entered.complete();
                await release.future;
              }
              return EpubParserService().parseLazySection(
                identity: request.identity,
                html: request.html,
                section: request.section,
                resourceBytes: request.resourceBytes,
                resourceMediaTypes: request.resourceMediaTypes,
                footnoteContentById: request.footnoteContentById,
              );
            },
          ),
        );
        Future<ParsedSection>? warmup;
        try {
          final index = await session.open(epub);
          await session.loadAround(session.initialLocation(), after: 0);
          expect(starts, [0]);
          if (holdWarmup) {
            warmup = session.loadSection(
              6,
              priority: LazySectionWorkPriority.boundaryPrefetch,
            );
            await entered.future;
          }
          final target = session.resolveChapterTarget(index.chapters[5])!;
          expect(target.spineIndex, 5);
          final request = session.prepareNavigation(
            target,
            canCommit: () => true,
          );
          final identity = LazySectionIdentity.fromIndexItem(
            bookId: index.bookId,
            publicationFingerprint: index.publicationFingerprint,
            item: index.spine[5],
            sourceChecksum: index.spine[5].sourceChecksum,
            dependencySignature: lazySectionDependencySignature(index),
          );
          bool? preempted;
          if (holdWarmup) {
            for (
              var step = 0;
              step < 100 && coordinator.stateFor(identity) == null;
              step++
            ) {
              await Future<void>(() {});
            }
            // Observe the scheduler after demand is registered. Do not require
            // the defective queued state: a real preemption fix may run it.
            expect(coordinator.stateFor(identity), isNotNull);
            expect(
              coordinator.priorityFor(identity),
              LazySectionWorkPriority.explicitNavigation,
            );
            // ignore: avoid_print
            print('DIRECT targetState=${coordinator.stateFor(identity)?.name}');
            preempted = starts.contains(5);
            release.complete();
          }
          final result = await request;
          expect(result.superseded, isFalse);
          expect(result.resolution.location!.spineIndex, 5);
          expect(starts.where((i) => i >= 1 && i <= 4), isEmpty);
          expect(starts, holdWarmup ? [0, 6, 5] : [0, 5]);
          // ignore: avoid_print
          print(
            'DIRECT starts=$starts intermediate=0 preemptedBeforeRelease=$preempted',
          );
          if (holdWarmup) {
            expect(
              preempted,
              isTrue,
              reason:
                  'Explicit target remains queued behind held boundaryPrefetch; no preemption before parser release.',
            );
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await warmup;
          await session.close();
        }
      },
    );
  }
}
