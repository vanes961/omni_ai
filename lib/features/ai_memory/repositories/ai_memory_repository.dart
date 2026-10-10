import 'package:omni_ai/features/ai_memory/models/ai_memory.dart';

abstract interface class AIMemoryRepository {
  Future<List<AIMemory>> getAll();

  Future<void> save(AIMemory memory);

  Future<void> delete(String id);

  Future<void> dispose();
}
