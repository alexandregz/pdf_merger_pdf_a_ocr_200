import 'package:flutter/material.dart';

// ======================== utilidade de modal bloqueante ========================

/// Estados posibles do proceso (para o modal)
enum TaskState { working, doneOk, doneError }

/// Controlador simple para enviar mensaxes ao modal e marcar cando remata.
class TaskProgressController {
  final ValueNotifier<String> log = ValueNotifier<String>('');
  final ValueNotifier<TaskState> state =
      ValueNotifier<TaskState>(TaskState.working);

  /// Engade unha liña ao log (con salto final se falta).
  void append(String s) {
    final line = s.endsWith('\n') ? s : '$s\n';
    log.value = log.value + line;
  }

  /// Marca proceso como finalizado OK.
  void finishOk() {
    state.value = TaskState.doneOk;
  }

  /// Marca proceso como finalizado con ERRO.
  void finishError() {
    state.value = TaskState.doneError;
  }

  /// (Opcional) Limpa para unha nova execución.
  void reset() {
    log.value = '';
    state.value = TaskState.working;
  }
}

/// Mostra un modal bloqueante cun log en tempo real.
/// - Escurece o fondo e bloquea toda a app.
/// - Non permite pechar ata que `controller.done.value == true` (aparece botón Pechar).
Future<void> showProgressLogDialog(
  BuildContext context,
  TaskProgressController controller, {
  String title = 'Procesando…',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Progreso',
    barrierColor: Colors.black.withValues(alpha: 0.6), // fondo escurecido
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, anim1, anim2) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
          child: _ProgressLogDialog(title: title, controller: controller),
        ),
      );
    },
  );
}

class _ProgressLogDialog extends StatefulWidget {
  const _ProgressLogDialog({required this.title, required this.controller});
  final String title;
  final TaskProgressController controller;

  @override
  State<_ProgressLogDialog> createState() => _ProgressLogDialogState();
}

class _ProgressLogDialogState extends State<_ProgressLogDialog> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.log.addListener(_autoScroll);
  }

  @override
  void dispose() {
    widget.controller.log.removeListener(_autoScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 20,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeceira
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  ValueListenableBuilder<TaskState>(
                    valueListenable: widget.controller.state,
                    builder: (_, st, __) {
                      switch (st) {
                        case TaskState.working:
                          return const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          );
                        case TaskState.doneOk:
                          return const Icon(Icons.check_circle,
                              color: Colors.green);
                        case TaskState.doneError:
                          return const Icon(Icons.cancel, color: Colors.red);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Corpo: área de log
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.controller.log,
                builder: (_, logText, __) {
                  final text = logText.isEmpty ? 'Inicializando…' : logText;
                  return Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    padding: const EdgeInsets.all(12),
                    child: Scrollbar(
                      controller: _scroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        child: SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Pé: botón de pechar (só cando remata)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Spacer(),
                  ValueListenableBuilder<TaskState>(
                    valueListenable: widget.controller.state,
                    builder: (_, st, __) {
                      final done = st != TaskState.working;
                      return FilledButton.icon(
                        onPressed:
                            done ? () => Navigator.of(context).pop() : null,
                        icon: const Icon(Icons.close),
                        label: const Text('Pechar'),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
