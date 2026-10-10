import 'package:flutter/material.dart';
import 'package:omni_ai/features/ai_memory/models/ai_memory.dart';
import 'package:omni_ai/features/ai_memory/repositories/ai_memory_repository.dart';

class AIMemoryManagerDialog extends StatefulWidget {
  const AIMemoryManagerDialog({required this.repository, super.key});

  final AIMemoryRepository repository;

  @override
  State<AIMemoryManagerDialog> createState() => _AIMemoryManagerDialogState();
}

class _AIMemoryManagerDialogState extends State<AIMemoryManagerDialog> {
  final TextEditingController _input = TextEditingController();
  List<AIMemory> _memories = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final memories = await widget.repository.getAll();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted)
        setState(() => _error = 'Не удалось загрузить память: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final content = _input.text.trim();
    if (content.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      await widget.repository.save(
        AIMemory(
          id: now.microsecondsSinceEpoch.toString(),
          content: content,
          createdAt: now,
        ),
      );
      if (!mounted) return;
      _input.clear();
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Не удалось сохранить: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(AIMemory memory) async {
    try {
      await widget.repository.delete(memory.id);
      await _reload();
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Не удалось удалить: $error');
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Долговременная память'),
      content: SizedBox(
        width: 480,
        height: 430,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Сохраняется только то, что вы добавите здесь. Эти записи '
              'хранятся на устройстве отдельно от переписки.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _input,
              minLines: 2,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Что запомнить?',
                hintText: 'Например: предпочитаю краткие ответы',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_saving ? 'Сохранение…' : 'Сохранить'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(),
            const Text(
              'Сохранённые записи',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _memories.isEmpty
                  ? const Center(child: Text('Пока ничего не сохранено.'))
                  : ListView.separated(
                      itemCount: _memories.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final memory = _memories[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(memory.content),
                          subtitle: Text(
                            '${memory.createdAt.toLocal()}'.split('.').first,
                          ),
                          trailing: IconButton(
                            tooltip: 'Удалить воспоминание',
                            onPressed: () => _delete(memory),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
