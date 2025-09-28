import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  // Necesario para inicializar plugins antes de runApp
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 👇 Cambiar título da xanela
  await windowManager.setTitle('CIG Combinador PDF - OCR · PDF/A');

  // 👇 Fixar tamaño mínimo da xanela
  await windowManager.setMinimumSize(const Size(900, 600));

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Combinador PDF/A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const MinimalHome(),
    );
  }
}

class MinimalHome extends StatefulWidget {
  const MinimalHome({super.key});
  @override
  State<MinimalHome> createState() => _MinimalHomeState();
}

class _MinimalHomeState extends State<MinimalHome> {
  final List<File> _files = [];
  bool _dragging = false;
  bool _busy = false;
  double _progress = 0.0;
  String _log = '';
  // --- [MODAL LOG - engadido] controlador do modal activo (se existe) ---
  TaskProgressController? _activeCtrl;

  static const int fourGB = 4 * 1024 * 1024 * 1024; // 4 GiB

  // rutas resoltas das ferramentas
  final Map<String, String> _tool = {
    'qpdf': '',
    'ocrmypdf': '',
    'tesseract': '',
    'gs': '',
  };

  void _logAdd(String s) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = s.endsWith('\n') ? s : ('$s\n');
    setState(() => _log += '[$ts] $line');
    // modal
    _activeCtrl?.append('[$ts] $line');
  }

  // ========================= Helpers PATH/login shell & exec (Olho, macos!) =========================

  String get _userShell => Platform.environment['SHELL'] ?? '/bin/zsh';

  // Executa unha orde no login shell (carga ~/.zprofile) para ter PATH real
  Future<ProcessResult> _runInLoginShell(String commandLine) {
    return Process.run(_userShell, ['-lc', commandLine]);
  }

  String _sh(String s) => "'${s.replaceAll("'", r"'\''")}'";

  // Fallback robusto: intenta exec directo; se EPERM, executa vía login shell
  Future<ProcessResult> _runWithFallback(String exeAbs, List<String> args) async {
    try {
      return await Process.run(exeAbs, args);
    } on ProcessException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('operation not permitted') || msg.contains('eperm')) {
        final cmd = [_sh(exeAbs), ...args.map(_sh)].join(' ');
        return await _runInLoginShell(cmd);
      }
      rethrow;
    }
  }

  // Resolve a ruta absoluta dun comando co login shell (command -v),
  // e con candidatos típicos (Homebrew/MacPorts/Python framework)
  Future<String?> _which(String name) async {
    final res = await _runInLoginShell('command -v ${_sh(name)} || true');
    if (res.exitCode == 0) {
      final out = (res.stdout as String).trim();
      if (out.isNotEmpty && out != name) return out;
    }
    const candidates = [
      '/opt/homebrew/bin', // Apple Silicon (Homebrew)
      '/usr/local/bin',    // Intel (Homebrew)
      '/opt/local/bin',    // MacPorts
      '/usr/bin', '/bin',
      '/Library/Frameworks/Python.framework/Versions/3.12/bin',
      '/Library/Frameworks/Python.framework/Versions/3.11/bin',
    ];
    for (final d in candidates) {
      final pth = '$d/$name';
      if (File(pth).existsSync()) return pth;
    }
    return null;
  }

  // ===================== Resolver ferramentas e --version =====================

  Future<bool> _resolveToolsAndCheckVersions() async {
    _logAdd('Resolvéndose rutas das ferramentas co PATH do usuario...');
    _tool['qpdf']      = (await _which('qpdf')) ?? '';
    _tool['ocrmypdf']  = (await _which('ocrmypdf')) ?? '';
    _tool['tesseract'] = (await _which('tesseract')) ?? '';
    _tool['gs']        = (await _which('gs')) ?? '';

    _logAdd('qpdf      -> ${_tool['qpdf']!.isEmpty ? 'NON ATOPADO' : _tool['qpdf']}');
    _logAdd('ocrmypdf  -> ${_tool['ocrmypdf']!.isEmpty ? 'NON ATOPADO' : _tool['ocrmypdf']}');
    _logAdd('tesseract -> ${_tool['tesseract']!.isEmpty ? 'NON ATOPADO' : _tool['tesseract']}');
    _logAdd('gs        -> ${_tool['gs']!.isEmpty ? 'NON ATOPADO' : _tool['gs']}');

    Future<bool> tryVersion(String key) async {
      final exe = _tool[key]!;
      if (exe.isEmpty) return false;
      try {
        final r = await _runWithFallback(exe, ['--version']);
        final first = (r.stdout is String ? r.stdout as String : '').split('\n').first.trim();
        _logAdd('[$key --version] exit=${r.exitCode}${first.isNotEmpty ? ' · ' + first : ''}');
        return r.exitCode == 0;
      } catch (e) {
        _logAdd('Erro lanzando $exe --version: $e');
        return false;
      }
    }

    final okQ = await tryVersion('qpdf');
    final okO = await tryVersion('ocrmypdf');
    await tryVersion('tesseract'); // informativos
    await tryVersion('gs');

    final ok = okQ && okO;
    if (!ok) _logAdd('Ferramentas obrigatorias non listas (precísanse qpdf e ocrmypdf).');
    return ok;
  }

  // ============================== Execución proceso ==============================

  Future<bool> _run(String key, List<String> args) async {
    final exe = _tool[key] ?? '';
    if (exe.isEmpty) {
      _logAdd('Comando non resolto: $key');
      return false;
    }
    _logAdd('Exec: $exe ${args.join(' ')}');
    try {
      final r = await _runWithFallback(exe, args);
      final out = (r.stdout is String ? r.stdout as String : '').trim();
      final err = (r.stderr is String ? r.stderr as String : '').trim();
      if (out.isNotEmpty) _logAdd('[stdout $key] $out');
      if (err.isNotEmpty) _logAdd('[stderr $key] $err');
      _logAdd('$key -> exitCode ${r.exitCode}');
      return r.exitCode == 0;
    } catch (e) {
      _logAdd('Non se puido executar "$exe": $e');
      return false;
    }
  }


  // ============================== Fluxo principal UI ==============================

  Future<void> _pickFiles() async {
    //_logAdd('Abrindo diálogo para seleccionar PDFs...');
    final typeGroup = XTypeGroup(label: 'PDFs', extensions: ['pdf']);
    final result = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (result.isEmpty) {
      //_logAdd('Non se seleccionou ningún ficheiro.');
      return;
    }
    setState(() => _files.addAll(result.map((x) => File(x.path))));
    //_logAdd('Engadidos ${result.length} PDF(s).');
  }

  Future<void> _generate() async {
    //_logAdd('--- PREMEU "Xerar PDF" ---');
    if (_files.isEmpty) {
      _logAdd('Lista baleira: arrastra PDFs ou preme Engadir.');
      return;
    }

    // --- [MODAL - engadido] abrir modal bloqueante con spinner e log en tempo real ---
    // --- Mostrar modal de progreso de inmediato ao colocalo aqui ---
    final ctrl = TaskProgressController();
    _activeCtrl = ctrl;
    // non agardes ao peche: que apareza xa
    // ignore: unawaited_futures
    showProgressLogDialog(context, ctrl, title: 'Xerando PDF…');

    // cede un frame para que a modal se pinte antes de comezar traballos
    await Future.delayed(const Duration(milliseconds: 16));


    // 0) resolver rutas e validar --version
    final toolsOk = await _resolveToolsAndCheckVersions();
    if (!toolsOk) return;

    // Estimación (suma * 1.2)
    final int sum = _files.fold<int>(
        0, (s, f) => s + (f.existsSync() ? f.lengthSync() : 0));
    final int estimate = (sum * 1.2).toInt();
    _logAdd('Estimación de tamaño tras OCR ~ ${_fmt(estimate)} (sumados ${_fmt(sum)}).');
    if (estimate > fourGB) {
      _logAdd('Estimación supera 4GB. Abortando.');
      return;
    }

    final location =
        await getSaveLocation(suggestedName: 'documento_final.pdf');
    if (location == null) {
      //_logAdd('Cancelado polo usuario (non se escolleu destino).');
      return;
    }
    final savePath = location.path;

    setState(() {
      _busy = true;
      _progress = 0.01;
    });



    //final swTotal = Stopwatch()..start(); // se comentamos _logAdd(${swTotal.elapsed}) ==> comentamos isto
    final tmp = await Directory.systemTemp.createTemp('pdfmerge_min_');
    final mergedRaw = p.join(tmp.path, 'merged_raw.pdf');
    final mergedFinal = p.join(tmp.path, 'merged_final.pdf');

    try {
      // 1) Merge con qpdf
      _logAdd('Unindo con qpdf...');
      setState(() => _progress = 0.2);
      final qpdfArgs = [
        '--empty',
        '--pages',
        ..._files.map((f) => f.path),
        '--',
        mergedRaw
      ];
      //_logAdd('CMD: qpdf ${qpdfArgs.join(' ')}');
      final sw = Stopwatch()..start();
      final okMerge = await _run('qpdf', qpdfArgs);
      _logAdd('qpdf durou ${sw.elapsed}');
      if (!okMerge) {
        _logAdd('qpdf fallou. Abortando.');
        return;
      }

      // 2) Límite 4GB despois de unir
      final mSize = File(mergedRaw).lengthSync();
      _logAdd('Tamaño tras unión: ${_fmt(mSize)}');
      if (mSize > fourGB) {
        _logAdd('O unido supera 4GB. Abortando.');
        return;
      }

      // 3) OCR + PDF/A + 200 dpi con ocrmypdf
      _logAdd('Aplicando OCR + PDF/A (200 dpi) ...');
      setState(() => _progress = 0.6);
      final ocrArgs = [
        '--output-type',
        'pdfa',
        '--optimize',
        '3',
        '--pdfa-image-compression',
        'lossless',
        '--jobs',
        Platform.numberOfProcessors.toString(),
        '--redo-ocr',
        '--oversample',
        '200',
        mergedRaw,
        mergedFinal,
      ];
      //_logAdd('CMD: ocrmypdf ${ocrArgs.join(' ')}');
      final sw2 = Stopwatch()..start();
      final okOcr = await _run('ocrmypdf', ocrArgs);
      _logAdd('ocrmypdf durou ${sw2.elapsed}');
      if (!okOcr) {
        _logAdd('ocrmypdf fallou. Abortando.');
        return;
      }

      // 4) Límite final e gardar
      final fSize = File(mergedFinal).lengthSync();
      _logAdd('Tamaño final: ${_fmt(fSize)}');
      if (fSize > fourGB) {
        _logAdd('Resultado supera 4GB. Non se gardará.');
        return;
      }

      await File(mergedFinal).copy(savePath);
      //_logAdd('Feito en ${swTotal.elapsed}. Gardado en: $savePath');
    } catch (e, st) {
      _logAdd('Erro: $e');
      _logAdd(st.toString());
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
      setState(() {
        _busy = false;
        _progress = 0.0;
      });

      // --- [MODAL - engadido] rematar modal e limpar referencia ---
    _activeCtrl?.finish();
    _activeCtrl = null;
    }
  }

  static String _fmt(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double b = bytes.toDouble();
    int i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(2)} ${units[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final est = (() {
      final s = _files.fold<int>(
          0, (a, f) => a + (f.existsSync() ? f.lengthSync() : 0));
      return (s * 1.2).toInt();
    })();
    final over = est > fourGB;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unir PDF · OCR · PDF/A (200 dpi)'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _generate,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Xerar PDF'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Engadir'),
                ),
                const SizedBox(width: 24),
                if (_busy)
                  Expanded(child: LinearProgressIndicator(value: _progress))
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Card(
                    margin: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          dense: true,
                          title: const Text(
                            'Arrastra aquí os PDF (podes reordenar)',
                          ),
                          trailing: Text(
                            'Estimación: ${_fmt(est)}',
                            style: TextStyle(
                              color: over ? Colors.red : null,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: DropTarget(
                            onDragEntered: (_) =>
                                setState(() => _dragging = true),
                            onDragExited: (_) =>
                                setState(() => _dragging = false),
                            onDragDone: (d) {
                              setState(() => _files.addAll(d.files
                                  .where((f) => f.path
                                      .toLowerCase()
                                      .endsWith('.pdf'))
                                  .map((f) => File(f.path))));
                              //_logAdd('Arrastrados ${d.files.length} elemento(s).');
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _dragging ? Colors.blue : Colors.grey,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ReorderableListView.builder(
                                itemCount: _files.length,
                                onReorder: (o, n) {
                                  setState(() {
                                    if (n > o) n--;
                                    final it = _files.removeAt(o);
                                    _files.insert(n, it);
                                    //_logAdd('Reordenado $o -> $n');
                                  });
                                },
                                itemBuilder: (c, i) {
                                  final f = _files[i];
                                  final size = _fmt(
                                      f.existsSync() ? f.lengthSync() : 0);
                                  return ListTile(
                                    key: ValueKey(f.path),
                                    leading: const Icon(Icons.picture_as_pdf),
                                    title: Text(p.basename(f.path)),
                                    subtitle: Text(size),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: _busy
                                          ? null
                                          : () => setState(
                                              () => _files.removeAt(i)),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ListTile(dense: true, title: Text('Log')),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                                _log.isEmpty ? 'Sen log.' : _log),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ======================== [ENGADIDO] utilidade de modal bloqueante ========================

/// Controlador simple para enviar mensaxes ao modal e marcar cando remata.
class TaskProgressController {
  final ValueNotifier<String> log = ValueNotifier<String>('');
  final ValueNotifier<bool> done = ValueNotifier<bool>(false);

  /// Engade unha liña ao log (con salto final se falta).
  void append(String s) {
    final line = s.endsWith('\n') ? s : '$s\n';
    log.value = log.value + line;
  }

  /// Marca o proceso como finalizado (activa botón Pechar).
  void finish() {
    done.value = true;
  }

  /// (Opcional) Limpa para unha nova execución.
  void reset() {
    log.value = '';
    done.value = false;
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
    barrierColor: Colors.black.withOpacity(0.6), // fondo escurecido
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
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.controller.done,
                    builder: (_, done, __) {
                      return done
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            );
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
                        .withOpacity(0.4),
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
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.controller.done,
                    builder: (_, done, __) {
                      return FilledButton.icon(
                        onPressed: done ? () => Navigator.of(context).pop() : null,
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
