import 'package:omni_ai/features/run_history/models/process_run_record.dart';

abstract interface class RunHistoryRepository {
  Stream<List<ProcessRunRecord>> watch();

  Future<List<ProcessRunRecord>> getAll();

  Future<void> save(ProcessRunRecord record);

  Future<void> delete(String id);

  Future<void> dispose();
}
