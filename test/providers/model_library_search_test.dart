import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/providers/model_library_provider.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_hub_client.dart';
import 'package:vitalis_app/services/persistent_hub_search_cache.dart';

HubSearchPage page(String id, {Uri? next}) => HubSearchPage(
  models: [
    HubModelSummary(
      id: id,
      revision: 'immutable',
      tags: const ['gguf'],
      downloads: 1,
      gated: false,
    ),
  ],
  nextUrl: next,
);
void main() {
  for (final cached in [false, true]) {
    test(
      'pagination deduplicates ${cached ? 'fresh cached' : 'network'} results',
      () async {
        final hub = _Hub();
        final next = HubSearchPage(
          models: [
            ...page('old').models,
            ...page('next-model').models,
            ...page('next-model').models,
          ],
        );
        final provider = ModelLibraryProvider(
          hub: hub,
          registry: _Registry(),
          downloads: _Downloads(),
          searchCache: cached ? _CursorCache(next) : _Cache(),
        );
        addTearDown(provider.dispose);
        await provider.search('old');
        final pending = provider.loadMore();
        if (!cached) {
          await hub.entered.future;
          hub.more.complete(next);
        }
        await pending;
        expect(provider.results.map((model) => model.id), [
          'old',
          'next-model',
        ]);
        expect(provider.status, ModelLibraryStatus.ready);
        expect(provider.canLoadMore, isFalse);
        expect(hub.calls.length, cached ? 1 : 2);
        await provider.loadMore();
        expect(hub.calls.length, cached ? 1 : 2);
      },
    );
  }
  test('fresh cache serves results without a Hub request', () async {
    final hub = _Hub();
    final cache = _StoredCache(
      HubSearchCacheEntry(
        page: page('cached'),
        fetchedAt: DateTime(2026),
        isFresh: true,
      ),
    );
    final provider = ModelLibraryProvider(
      hub: hub,
      registry: _Registry(),
      downloads: _Downloads(),
      searchCache: cache,
    );
    addTearDown(provider.dispose);
    await provider.search('  Fixture  ', publisher: '  Publisher  ');
    expect(hub.calls, isEmpty);
    expect(provider.results.single.id, 'cached');
    expect(provider.status, ModelLibraryStatus.ready);
    expect(cache.keys.single, contains('publisher=publisher'));
  });
  for (final cached in [true, false]) {
    test(
      'offline search ${cached ? 'retains stale results' : 'exposes an actionable error'}',
      () async {
        final hub = _Hub()..offline = true;
        final cache = _StoredCache(
          cached
              ? HubSearchCacheEntry(
                  page: page('stale'),
                  fetchedAt: DateTime(2026),
                  isFresh: false,
                )
              : null,
        );
        final provider = ModelLibraryProvider(
          hub: hub,
          registry: _Registry(),
          downloads: _Downloads(),
          searchCache: cache,
        );
        addTearDown(provider.dispose);
        await provider.search(' Fixture ', publisher: ' Publisher ');
        expect(hub.calls, [('Fixture', 'Publisher')]);
        expect(
          provider.status,
          cached ? ModelLibraryStatus.offline : ModelLibraryStatus.error,
        );
        if (cached) {
          expect(provider.results.single.id, 'stale');
        } else {
          expect(provider.results, isEmpty);
          expect(provider.error, isNotNull);
        }
      },
    );
  }
  test('empty Hub results settle loading without an error', () async {
    final provider = ModelLibraryProvider(
      hub: _Hub(),
      registry: _Registry(),
      downloads: _Downloads(),
      searchCache: _Cache(),
    );
    addTearDown(provider.dispose);
    await provider.search('empty');
    expect(provider.status, ModelLibraryStatus.empty);
    expect(provider.results, isEmpty);
    expect(provider.canLoadMore, isFalse);
    expect(provider.error, isNull);
  });
  test(
    'cache persistence failure does not discard successful Hub results',
    () async {
      final provider = ModelLibraryProvider(
        hub: _Hub(),
        registry: _Registry(),
        downloads: _Downloads(),
        searchCache: _FailedWriteCache(),
      );
      addTearDown(provider.dispose);
      await provider.search('new');
      expect(provider.results.map((item) => item.id), ['new']);
      expect(provider.status, ModelLibraryStatus.ready);
      expect(provider.error, isNull);
      expect(provider.cacheState, ModelLibraryCacheState.writeFailed);
    },
  );
  test('late cache write cannot replace newer query results', () async {
    final cache = _WaitingCache();
    final provider = ModelLibraryProvider(
      hub: _Hub(),
      registry: _Registry(),
      downloads: _Downloads(),
      searchCache: cache,
    );
    addTearDown(provider.dispose);
    final old = provider.search('old');
    await cache.entered.future;
    await provider.search('new');
    cache.finished.complete();
    await old;
    expect(provider.results.map((item) => item.id), ['new']);
    expect(provider.status, ModelLibraryStatus.ready);
  });
  for (final disposed in [false, true]) {
    test(
      'old pagination failure cannot ${disposed ? 'publish after disposal' : 'mark newer search offline'}',
      () async {
        final hub = _Hub();
        final provider = ModelLibraryProvider(
          hub: hub,
          registry: _Registry(),
          downloads: _Downloads(),
          searchCache: _Cache(),
        );
        addTearDown(provider.dispose);
        await provider.search('old');
        final pending = provider.loadMore();
        await hub.entered.future;
        if (disposed) {
          provider.dispose();
        } else {
          await provider.search('new');
        }
        hub.more.completeError(StateError('fixture offline'));
        await pending;
        if (disposed) {
          await expectLater(provider.search('new'), throwsStateError);
          await expectLater(provider.loadMore(), throwsStateError);
        } else {
          expect(provider.status, ModelLibraryStatus.ready);
          expect(provider.results.map((item) => item.id), ['new']);
        }
      },
    );
  }
  test('old pagination cannot append into a newer search', () async {
    final hub = _Hub();
    final provider = ModelLibraryProvider(
      hub: hub,
      registry: _Registry(),
      downloads: _Downloads(),
      searchCache: _Cache(),
    );
    addTearDown(provider.dispose);
    await provider.search('old');
    final pending = provider.loadMore();
    await hub.entered.future;
    await provider.search('new');
    hub.more.complete(page('old-page'));
    await pending;
    expect(provider.results.map((model) => model.id), ['new']);
  });
}

class _Hub implements ModelHubClient {
  bool offline = false;
  final calls = <(String, String?)>[];
  final more = Completer<HubSearchPage>();
  final entered = Completer<void>();
  @override
  Future<HubSearchPage> search({
    String query = '',
    HubSort sort = HubSort.downloads,
    String? publisher,
    int limit = 20,
    Uri? page,
  }) async {
    calls.add((query, publisher));
    if (offline) throw StateError('fixture offline');
    if (query == 'empty') return const HubSearchPage(models: []);
    if (page != null) {
      entered.complete();
      return more.future;
    }
    return _result(query);
  }

  HubSearchPage _result(String query) => page(
    query,
    next: query == 'old'
        ? Uri.parse('https://huggingface.co/api/models?cursor=fixture')
        : null,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Hub operation');
}

class _Cache implements PersistentHubSearchCache {
  @override
  Future<HubSearchCacheEntry?> read(String key) async => null;
  @override
  Future<void> write(String key, HubSearchPage page) async {}
  @override
  Future<void> prune() async {}
}

class _StoredCache extends _Cache {
  _StoredCache(this.entry);
  final HubSearchCacheEntry? entry;
  final keys = <String>[];
  @override
  Future<HubSearchCacheEntry?> read(String key) async {
    keys.add(key);
    return entry;
  }
}

class _CursorCache extends _Cache {
  _CursorCache(this.page);
  final HubSearchPage page;
  @override
  Future<HubSearchCacheEntry?> read(String key) async =>
      key.contains('cursor=') && !key.endsWith('cursor=')
      ? HubSearchCacheEntry(
          page: page,
          fetchedAt: DateTime(2026),
          isFresh: true,
        )
      : null;
}

class _WaitingCache extends _Cache {
  final entered = Completer<void>();
  final finished = Completer<void>();
  @override
  Future<void> write(String key, HubSearchPage page) async {
    if (page.models.first.id == 'old') {
      entered.complete();
      await finished.future;
    }
  }
}

class _FailedWriteCache extends _Cache {
  @override
  Future<void> write(String key, HubSearchPage page) async =>
      throw StateError('fixture cache disk failure');
}

class _Registry implements ModelRegistryService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected registry operation');
}

class _Downloads implements ModelDownloadManager {
  @override
  void addJobListener(void Function(ModelDownloadJob) listener) {}
  @override
  void removeJobListener(void Function(ModelDownloadJob) listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected download operation');
}
