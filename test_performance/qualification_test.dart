import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final suite = Platform.environment['VITALIS_PERF_SUITE'];
  final policy =
      jsonDecode(File('tool/perf/policy.json').readAsStringSync())
          as Map<String, dynamic>;
  final output = Platform.environment['VITALIS_PERF_METRICS'];
  final count = policy['cases'] as int;
  Directory? sandbox;
  LlamaCppChatRepository? owner;
  final database = DatabaseHelper.instance;
  final native = suite == 'throughput' || suite == 'concurrency';
  final storage = suite == 'stress' || suite == 'volume';
  setUpAll(() async {
    expect([
      'throughput',
      'stress',
      'spike',
      'volume',
      'concurrency',
    ], contains(suite));
    expect(output, isNotNull, reason: 'Metrics destination is mandatory');
    sandbox = await Directory.systemTemp.createTemp('vitalis-perf-$suite-');
    if (native) {
      final model = File(Platform.environment['VITALIS_TEST_MODEL'] ?? '');
      expect(
        await model.exists(),
        isTrue,
        reason: 'Native fixture must not skip',
      );
      expect(
        (await sha256.bind(model.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      owner = LlamaCppChatRepository.withModelPath(
        model.path,
        contextSize: policy['native_context'] as int,
        batchSize: policy['native_batch'] as int,
        threads: policy['native_threads'] as int,
        promptThreads: policy['native_threads'] as int,
        supportsThinkingControl: true,
      );
      await owner!.prepare();
    }
    if (storage) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(sandbox!.path);
      await database.database;
    }
  });
  tearDownAll(() async {
    await owner?.close();
    if (storage) await database.close();
    if (sandbox != null) await sandbox!.delete(recursive: true);
  });
  void record(int index, Map<String, Object?> values) {
    final row = {
      'suite': suite,
      'case': index + 1,
      'platform': Platform.operatingSystem,
      ...values,
    };
    File(output!).writeAsStringSync(
      '${jsonEncode(row)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  for (var index = 0; index < count; index++) {
    test('$suite sample ${index + 1}', () async {
      final watch = Stopwatch()..start();
      if (native) {
        final active = owner!;
        Future<void>? cancellation;
        var checked = false;
        var visible = 0;
        await for (final chunk in active.streamChatWithGenerationOptions(
          'perf-$index',
          messages: [
            LLMMessage(
              role: LLMRole.user,
              content: 'Count forward starting at ${index + 1}.',
            ),
          ],
          think: false,
          generationOptions: GenerationOptions(
            maxTokens: policy['native_output_tokens'] as int,
          ),
        )) {
          if (chunk.done != true) {
            visible++;
            if (suite == 'concurrency' && !checked) {
              checked = true;
              final competitor = LlamaCppChatRepository.withModelPath(
                Platform.environment['VITALIS_TEST_MODEL']!,
              );
              try {
                await expectLater(
                  competitor.prepare(),
                  throwsA(isA<InferenceRuntimeBusy>()),
                );
                await expectLater(
                  competitor.cancelActiveInference(),
                  throwsA(isA<InferenceRuntimeBusy>()),
                );
                await expectLater(
                  competitor.unloadPersistentModel(),
                  throwsA(isA<InferenceRuntimeBusy>()),
                );
              } finally {
                await competitor.close();
              }
              if (index.isOdd) cancellation = active.cancelActiveInference();
            }
          }
        }
        await cancellation;
        expect(visible, greaterThan(0));
        expect(active.cleanupFailed, isFalse);
        final metrics = active.lastMetrics!;
        expect(metrics.generatedTokens, greaterThan(0));
        expect(metrics.generationMicros, greaterThan(0));
        expect(metrics.generatedTokensPerSecond.isFinite, isTrue);
        if (suite == 'concurrency') expect(checked, isTrue);
        record(index, {
          'generated_tokens': metrics.generatedTokens,
          'generation_micros': metrics.generationMicros,
          'generation_tokens_per_second': metrics.generatedTokensPerSecond,
          'prompt_tokens': metrics.promptTokens,
          'prompt_eval_micros': metrics.promptEvalMicros,
          'helper_first_emission_micros': metrics.timeToFirstTokenMicros,
          'completion_reason': metrics.completionReason,
          'cancellation_ack_micros': metrics.cancellationAcknowledgementMicros,
          'competing_operations_rejected': checked ? 3 : 0,
          'elapsed_micros': watch.elapsedMicroseconds,
          'scope':
              'Real immutable-model host CPU runtime; not Android model speed or UI TTFT',
        });
      } else if (suite == 'spike') {
        final target = '${sandbox!.path}/lease-$index.gguf';
        final burst = index + 2;
        var rejected = 0;
        await LlamaCppChatRepository.withModelFilesMutation([target], () async {
          await Future.wait(
            List.generate(burst, (_) async {
              await expectLater(
                LlamaCppChatRepository.withModelFilesMutation([
                  target,
                ], () async {}),
                throwsA(isA<InferenceRuntimeBusy>()),
              );
              rejected++;
            }),
          );
        });
        var recovered = false;
        await LlamaCppChatRepository.withModelFilesMutation([target], () async {
          recovered = true;
        });
        expect(rejected, burst);
        expect(recovered, isTrue);
        record(index, {
          'burst_requests': burst,
          'correct_busy_rejections': rejected,
          'recovered': recovered,
          'elapsed_micros': watch.elapsedMicroseconds,
          'scope':
              'Real production model-file reservation bursts; not UI taps or external HTTP load',
        });
      } else {
        final levels = List<int>.from(
          policy[suite == 'volume' ? 'volume_rows' : 'stress_rows'] as List,
        );
        final rows = levels[index % levels.length];
        final chat = await database.insertChat({
          'title': 'Performance fixture $index',
          'created_at': '2026-11-05T00:00:00Z',
          'updated_at': '2026-11-05T00:00:00Z',
        });
        try {
          final db = await database.database;
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (var row = 0; row < rows; row++) {
              batch.insert('messages', {
                'chat_id': chat,
                'role': row.isEven ? 'user' : 'assistant',
                'content':
                    'Fixture $row ${['Latin', '\u4e2d\u6587', '\u{1f642}'][index % 3]}',
                'timestamp': DateTime.utc(
                  2026,
                  11,
                  5,
                ).add(Duration(seconds: row)).toIso8601String(),
              });
            }
            await batch.commit(noResult: true);
          });
          if (suite == 'stress') {
            final fanout = index ~/ levels.length + 2;
            await Future.wait(
              List.generate(fanout, (_) async {
                final latest = await database.getMessagesForChatPaginated(
                  chat,
                  limit: 50,
                );
                expect(latest.length, 50);
                expect(
                  latest.last.content.startsWith('Fixture ${rows - 1} '),
                  isTrue,
                );
              }),
            );
            record(index, {
              'message_rows': rows,
              'concurrent_reads': fanout,
              'elapsed_micros': watch.elapsedMicroseconds,
              'scope': 'Bounded production SQLite history stress on CI host',
            });
          } else {
            final exported = await database.getAllMessagesForExport(chat);
            expect(exported.length, rows);
            expect(exported.first.content.startsWith('Fixture 0 '), isTrue);
            expect(
              exported.last.content.startsWith('Fixture ${rows - 1} '),
              isTrue,
            );
            final latest = await database.getMessagesForChatPaginated(
              chat,
              limit: 50,
            );
            final older = await database.getMessagesForChatPaginated(
              chat,
              limit: 50,
              beforeId: latest.first.id,
            );
            expect(older.length, 50);
            expect(older.last.id!, lessThan(latest.first.id!));
            record(index, {
              'message_rows': rows,
              'exported_rows': exported.length,
              'elapsed_micros': watch.elapsedMicroseconds,
              'scope':
                  'Production SQLite pagination and complete export at increasing volumes',
            });
          }
        } finally {
          await database.deleteChat(chat);
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
