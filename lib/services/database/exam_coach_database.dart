import 'package:path/path.dart' as path_util;
import 'package:sqflite/sqflite.dart';

class ExamCoachDatabase {
  ExamCoachDatabase({required this.databasePath, DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;

  static const schemaVersion = 8;
  static const fileName = 'exam_coach.sqlite';

  final String databasePath;
  final DatabaseFactory _factory;
  Database? _database;

  static Future<ExamCoachDatabase> openDefault() async {
    final directory = await getDatabasesPath();
    final database = ExamCoachDatabase(
      databasePath: path_util.join(directory, fileName),
    );
    await database.instance;
    return database;
  }

  Future<Database> get instance async {
    final current = _database;
    if (current != null && current.isOpen) {
      return current;
    }

    final opened = await _factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.transaction((transaction) async {
      await transaction.execute('''
        CREATE TABLE question_packs (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          exam_id TEXT NOT NULL,
          test_id TEXT NOT NULL,
          version INTEGER NOT NULL,
          validation_status TEXT NOT NULL,
          author TEXT NOT NULL,
          reviewer TEXT,
          generator_provider TEXT,
          generator_model TEXT,
          prompt_version TEXT,
          generated_at TEXT,
          reviewed_at TEXT,
          review_notes TEXT,
          provenance_decision TEXT,
          provenance_notes TEXT,
          content_sha256 TEXT,
          review_checklist_json TEXT,
          publisher TEXT,
          published_at TEXT,
          tryout_question_ids_json TEXT NOT NULL,
          downloaded_at TEXT NOT NULL
        )
      ''');
      await transaction.execute('''
        CREATE TABLE questions (
          id TEXT PRIMARY KEY,
          pack_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          prompt TEXT NOT NULL,
          options_json TEXT NOT NULL,
          correct_option_id TEXT NOT NULL,
          exam_id TEXT NOT NULL,
          test_id TEXT NOT NULL,
          domain_id TEXT NOT NULL,
          topic_id TEXT NOT NULL,
          subtopic_id TEXT NOT NULL,
          skill_id TEXT NOT NULL,
          micro_skill_id TEXT NOT NULL,
          topic_label TEXT NOT NULL,
          difficulty TEXT NOT NULL,
          cognitive_type TEXT NOT NULL,
          estimated_time_ms INTEGER NOT NULL,
          trap_type TEXT NOT NULL,
          provenance TEXT NOT NULL,
          author TEXT NOT NULL,
          reviewer TEXT,
          explanation TEXT NOT NULL,
          validation_status TEXT NOT NULL,
          content_version INTEGER NOT NULL,
          FOREIGN KEY (pack_id) REFERENCES question_packs(id) ON DELETE CASCADE
        )
      ''');
      await transaction.execute('''
        CREATE INDEX questions_pack_position_idx
        ON questions(pack_id, position)
      ''');
      await transaction.execute('''
        CREATE TABLE exam_sessions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          test_id TEXT NOT NULL,
          mode TEXT NOT NULL,
          status TEXT NOT NULL,
          question_ids_json TEXT NOT NULL,
          current_index INTEGER NOT NULL,
          started_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          ended_at TEXT,
          score INTEGER,
          sync_version INTEGER NOT NULL
        )
      ''');
      await transaction.execute('''
        CREATE INDEX exam_sessions_status_updated_idx
        ON exam_sessions(status, updated_at DESC)
      ''');
      await transaction.execute('''
        CREATE TABLE user_answers (
          session_id TEXT NOT NULL,
          question_id TEXT NOT NULL,
          position INTEGER NOT NULL,
          selected_option_id TEXT NOT NULL,
          correct_option_id TEXT NOT NULL,
          is_correct INTEGER NOT NULL,
          is_skipped INTEGER NOT NULL DEFAULT 0,
          time_spent_ms INTEGER NOT NULL,
          changed_answer INTEGER NOT NULL DEFAULT 0,
          answered_at TEXT NOT NULL,
          PRIMARY KEY (session_id, question_id),
          FOREIGN KEY (session_id) REFERENCES exam_sessions(id) ON DELETE CASCADE,
          FOREIGN KEY (question_id) REFERENCES questions(id)
        )
      ''');
      await transaction.execute('''
        CREATE INDEX user_answers_session_position_idx
        ON user_answers(session_id, position)
      ''');
      await transaction.execute('''
        CREATE TABLE weakness_profiles (
          taxonomy_node_id TEXT PRIMARY KEY,
          taxonomy_label TEXT NOT NULL,
          weakness_score REAL NOT NULL,
          confidence REAL NOT NULL,
          sample_size INTEGER NOT NULL,
          trend TEXT NOT NULL,
          tier TEXT NOT NULL,
          evidence_json TEXT NOT NULL,
          algorithm_version TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await transaction.execute('''
        CREATE TABLE recommendations (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          recommendation_type TEXT NOT NULL,
          target_taxonomy_id TEXT NOT NULL,
          target_label TEXT NOT NULL,
          priority INTEGER NOT NULL,
          reason_code TEXT NOT NULL,
          reason TEXT NOT NULL,
          expected_benefit TEXT NOT NULL,
          estimated_effort_ms INTEGER NOT NULL,
          confidence REAL NOT NULL,
          algorithm_version TEXT NOT NULL,
          generated_at TEXT NOT NULL,
          expires_at TEXT,
          FOREIGN KEY (session_id) REFERENCES exam_sessions(id) ON DELETE CASCADE
        )
      ''');
      await transaction.execute('''
        CREATE INDEX recommendations_generated_idx
        ON recommendations(generated_at DESC)
      ''');
      await _createAccountBindingSchema(transaction);
      await _createAiCoachSchema(transaction);
      await _createSyncSchema(transaction);
    });
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion > newVersion) {
      throw StateError(
        'Database downgrade is not supported: $oldVersion → $newVersion',
      );
    }

    var migratedVersion = oldVersion;
    if (migratedVersion < 2 && newVersion >= 2) {
      await database.transaction(_createSyncSchema);
      migratedVersion = 2;
    }
    if (migratedVersion < 3 && newVersion >= 3) {
      await database.transaction(_migrateContentMetadataV3);
      migratedVersion = 3;
    }
    if (migratedVersion < 4 && newVersion >= 4) {
      await database.transaction(_migrateSessionControlsV4);
      migratedVersion = 4;
    }
    if (migratedVersion < 5 && newVersion >= 5) {
      await database.transaction(_migrateSyncDeliveryV5);
      migratedVersion = 5;
    }
    if (migratedVersion < 6 && newVersion >= 6) {
      await database.transaction(_migrateContentReviewV6);
      migratedVersion = 6;
    }
    if (migratedVersion < 7 && newVersion >= 7) {
      await database.transaction(_createAccountBindingSchema);
      migratedVersion = 7;
    }
    if (migratedVersion < 8 && newVersion >= 8) {
      await database.transaction(_createAiCoachSchema);
      migratedVersion = 8;
    }
    if (migratedVersion != newVersion) {
      throw StateError(
        'Missing migration from schema $migratedVersion to $newVersion',
      );
    }
  }

  static Future<void> _migrateSessionControlsV4(
    DatabaseExecutor executor,
  ) async {
    await executor.execute(
      'ALTER TABLE user_answers ADD COLUMN is_skipped INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _migrateSyncDeliveryV5(DatabaseExecutor executor) async {
    final columns = await executor.rawQuery('PRAGMA table_info(sync_outbox)');
    final columnNames = columns.map((column) => column['name']).toSet();
    final additions = <String, String>{
      'last_attempt_at': 'TEXT',
      'next_attempt_at': 'TEXT',
      'synced_at': 'TEXT',
      'dead_lettered_at': 'TEXT',
      'acknowledgement': 'TEXT',
      'remote_revision': 'INTEGER',
    };
    for (final entry in additions.entries) {
      if (!columnNames.contains(entry.key)) {
        await executor.execute(
          'ALTER TABLE sync_outbox ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    await executor.execute('''
      UPDATE sync_outbox
      SET synced_at = created_at,
          acknowledgement = 'accepted'
      WHERE status = 'synced' AND synced_at IS NULL
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS sync_outbox_ready_idx
      ON sync_outbox(status, next_attempt_at, created_at)
    ''');
  }

  static Future<void> _migrateContentReviewV6(DatabaseExecutor executor) async {
    final columns = await executor.rawQuery(
      'PRAGMA table_info(question_packs)',
    );
    final columnNames = columns.map((column) => column['name']).toSet();
    final additions = <String, String>{
      'reviewed_at': 'TEXT',
      'review_notes': 'TEXT',
      'provenance_decision': 'TEXT',
      'provenance_notes': 'TEXT',
      'content_sha256': 'TEXT',
      'review_checklist_json': 'TEXT',
      'publisher': 'TEXT',
      'published_at': 'TEXT',
    };
    for (final entry in additions.entries) {
      if (!columnNames.contains(entry.key)) {
        await executor.execute(
          'ALTER TABLE question_packs ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<void> _migrateContentMetadataV3(
    DatabaseExecutor executor,
  ) async {
    await executor.execute(
      "ALTER TABLE question_packs ADD COLUMN title TEXT NOT NULL DEFAULT ''",
    );
    await executor.execute(
      "ALTER TABLE question_packs ADD COLUMN author TEXT NOT NULL DEFAULT 'legacy_import'",
    );
    await executor.execute(
      'ALTER TABLE question_packs ADD COLUMN reviewer TEXT',
    );
    await executor.execute(
      'ALTER TABLE question_packs ADD COLUMN generator_provider TEXT',
    );
    await executor.execute(
      'ALTER TABLE question_packs ADD COLUMN generator_model TEXT',
    );
    await executor.execute(
      'ALTER TABLE question_packs ADD COLUMN prompt_version TEXT',
    );
    await executor.execute(
      'ALTER TABLE question_packs ADD COLUMN generated_at TEXT',
    );
    await executor.execute(
      "ALTER TABLE question_packs ADD COLUMN tryout_question_ids_json TEXT NOT NULL DEFAULT '[]'",
    );
    await executor.execute(
      "ALTER TABLE questions ADD COLUMN author TEXT NOT NULL DEFAULT 'legacy_import'",
    );
    await executor.execute('ALTER TABLE questions ADD COLUMN reviewer TEXT');
    await executor.execute('''
      UPDATE question_packs
      SET title = 'Diagnostic TIU Prototype',
          author = 'examcoach_development_team',
          tryout_question_ids_json =
            '["q_ratio_01","q_ratio_02","q_sequence_01","q_sequence_02","q_analogy_01","q_analogy_02"]'
      WHERE id = 'pack_tiu_prototype_v1'
    ''');
    await executor.execute('''
      UPDATE questions
      SET author = 'examcoach_development_team'
      WHERE pack_id = 'pack_tiu_prototype_v1'
    ''');
  }

  static Future<void> _createSyncSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS analytics_events (
        id TEXT PRIMARY KEY,
        event_name TEXT NOT NULL,
        event_version INTEGER NOT NULL,
        occurred_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        session_id TEXT,
        properties_json TEXT NOT NULL,
        upload_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS analytics_events_upload_idx
      ON analytics_events(upload_status, occurred_at)
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        operation_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        last_error TEXT,
        last_attempt_at TEXT,
        next_attempt_at TEXT,
        synced_at TEXT,
        dead_lettered_at TEXT,
        acknowledgement TEXT,
        remote_revision INTEGER
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS sync_outbox_status_created_idx
      ON sync_outbox(status, created_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS sync_outbox_ready_idx
      ON sync_outbox(status, next_attempt_at, created_at)
    ''');
  }

  static Future<void> _createAccountBindingSchema(
    DatabaseExecutor executor,
  ) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS account_binding (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        firebase_uid TEXT NOT NULL UNIQUE,
        bound_at TEXT NOT NULL,
        last_recovered_at TEXT,
        remote_revision INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createAiCoachSchema(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ai_coach_insights (
        context_key TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        source_session_id TEXT NOT NULL,
        prompt_version TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        response_json TEXT NOT NULL,
        generated_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        FOREIGN KEY (source_session_id)
          REFERENCES exam_sessions(id) ON DELETE CASCADE
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS ai_coach_user_generated_idx
      ON ai_coach_insights(user_id, generated_at DESC)
    ''');
  }
}
