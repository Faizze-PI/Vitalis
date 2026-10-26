import 'dart:convert';

import '../database/database_helper.dart';
import '../models/hub_model.dart';

typedef HubSearchCacheClock = DateTime Function();

abstract final class HubSearchCachePolicy {
  static const freshFor = Duration(hours: 6);
  static const offlineRetention = Duration(days: 30);
  static const maximumEntries = 100; // hardcode: HC-035
}

class HubSearchCacheEntry {
  const HubSearchCacheEntry({
    required this.page,
    required this.fetchedAt,
    required this.isFresh,
  });

  final HubSearchPage page;
  final DateTime fetchedAt;
  final bool isFresh;
}

abstract interface class PersistentHubSearchCache {
  Future<HubSearchCacheEntry?> read(String key);
  Future<void> write(String key, HubSearchPage page);
  Future<void> prune();
}

class DatabaseHubSearchCache implements PersistentHubSearchCache {
  DatabaseHubSearchCache({
    DatabaseHelper? database,
    HubSearchCacheClock clock = DateTime.now,
  }) : _database = database ?? DatabaseHelper.instance,
       _clock = clock;

  final DatabaseHelper _database;
  final HubSearchCacheClock _clock;

  @override
  Future<HubSearchCacheEntry?> read(String key) async {
    final row = await _database.getHubSearchCache(key);
    if (row == null) return null;
    final now = _clock().toUtc();
    final fetchedAt = DateTime.parse(row['fetched_at']! as String).toUtc();
    if (now.difference(fetchedAt) > HubSearchCachePolicy.offlineRetention) {
      await prune();
      return null;
    }
    final decoded = jsonDecode(row['payload_json']! as String);
    if (decoded is! Map) return null;
    await _database.touchHubSearchCache(key, now);
    return HubSearchCacheEntry(
      page: HubSearchPage.fromJson(decoded.cast<String, Object?>()),
      fetchedAt: fetchedAt,
      isFresh: now.difference(fetchedAt) <= HubSearchCachePolicy.freshFor,
    );
  }

  @override
  Future<void> write(String key, HubSearchPage page) async {
    final now = _clock().toUtc().toIso8601String();
    await _database.upsertHubSearchCache({
      'cache_key': key,
      'payload_json': jsonEncode(page.toJson()),
      'fetched_at': now,
      'last_accessed_at': now,
    });
    await prune();
  }

  @override
  Future<void> prune() => _database.pruneHubSearchCache(
    oldestAllowed: _clock().toUtc().subtract(
      HubSearchCachePolicy.offlineRetention,
    ),
    maximumEntries: HubSearchCachePolicy.maximumEntries,
  );
}
