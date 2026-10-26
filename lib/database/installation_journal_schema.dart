import 'package:sqflite/sqflite.dart';

/// Durable intent only. Registry activation is a separate atomic projection
/// after every shard and the native compatibility probe have been validated.
Future<void> createInstallationJournalSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS model_installation_journal (
      operation_id TEXT PRIMARY KEY,
      job_id TEXT,
      model_id TEXT NOT NULL,
      repository TEXT,
      revision TEXT,
      phase TEXT NOT NULL CHECK (
        phase IN ('staging', 'validating', 'readyToInstall', 'projecting',
                  'installed', 'failed')
      ),
      state_revision INTEGER NOT NULL DEFAULT 0 CHECK (state_revision >= 0),
      expected_model_json TEXT NOT NULL,
      expected_files_json TEXT NOT NULL,
      validated_model_json TEXT,
      error_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE RESTRICT
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_installation_active_model
    ON model_installation_journal(model_id)
    WHERE phase NOT IN ('installed', 'failed')
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS model_installation_shards (
      operation_id TEXT NOT NULL,
      shard_index INTEGER NOT NULL CHECK (shard_index >= 0),
      shard_count INTEGER NOT NULL CHECK (shard_count > 0),
      file_name TEXT NOT NULL,
      byte_size INTEGER NOT NULL CHECK (byte_size > 0),
      expected_sha256 TEXT,
      actual_sha256 TEXT,
      hash_authority TEXT NOT NULL CHECK (
        hash_authority IN ('publisherSha256', 'immutableRevision', 'localIdentity')
      ),
      entity_tag TEXT,
      staging_path TEXT NOT NULL,
      final_path TEXT NOT NULL,
      validation_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (validation_state IN ('pending', 'validated')),
      moved INTEGER NOT NULL DEFAULT 0 CHECK (moved IN (0, 1)),
      PRIMARY KEY (operation_id, shard_index),
      UNIQUE (operation_id, file_name),
      UNIQUE (staging_path),
      CHECK (shard_index < shard_count),
      FOREIGN KEY (operation_id) REFERENCES model_installation_journal(operation_id)
        ON DELETE CASCADE
    )
  ''');
}
