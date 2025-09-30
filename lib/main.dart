// lib/main.dart
import 'dart:io';
import 'dart:async'; // engadido para streaming ocrmypdf
import 'dart:convert'; // engadido para decodificar stdout/stderr liña a liña

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

// <<< NOVO: módulo co bootstrap de micromamba >>>
import 'mamba_boot.dart';

Future<void> main() async {
  // Necesario para inicializar plugins antes de runApp
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Cambiar título da xanela
  await windowManager.setTitle('CIG Combinador PDF - OCR · PDF/A');

  // Fixar tamaño mínimo da xanela
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

  // --- Micromamba bootstrap (Windows) ---
  String? _mmRoot; // %LOCALAPPDATA%\CIG\tools\mm
  String? _mmBin; // %LOCALAPPDATA%\CIG\tools\mm\micromamba.exe
  String? _mmEnvRoot; // %LOCALAPPDATA%\CIG\tools\mm\envs\ocr-env
  String? _pythonExe; // %LOCALAPPDATA%\CIG\tools\mm\envs\ocr-env\python.exe

  // rutas resoltas das ferramentas
  final Map<String, String> _tool = {
    'qpdf': '',
    'ocrmypdf': '',
    'tesseract': '',
    'gs': '',
  };

  // Autoscroll Log
  late final ScrollController _logScroll;

  @override
  void initState() {
    super.initState();
    _logScroll = ScrollController();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }
  // ----------------------------------

  void _logAdd(String s) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = s.endsWith('\n') ? s : ('$s\n');
    setState(() => _log += '[$ts] $line');
    // duplicar log no modal se está aberto
    _activeCtrl?.append('[$ts] $line');

    // Autoscroll Log
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  // ========================= Helpers PATH/login shell & exec =========================

  // Executa unha orde no shell de login real do usuario en Unix
  // e en Windows usa cmd.exe /C (non existe zsh nin -lc).
  Future<ProcessResult> _runInLoginShell(String commandLine) {
    if (Platform.isWindows) {
      return Process.run('cmd.exe', ['/C', commandLine]);
    } else {
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      return Process.run(shell, ['-lc', commandLine]);
    }
  }

  String _sh(String s) => "'${s.replaceAll("'", r"'\''")}'";

  // Fallback robusto: intenta exec directo; se falla por EPERM, executa vía login shell
  Future<ProcessResult> _runWithFallback(
      String exeAbs, List<String> args) async {
    try {
      return await Process.run(exeAbs, args);
    } on ProcessException catch (e) {
      final msg =
          (e.message).toLowerCase(); // evitar uso de osError por compat.
      if (msg.contains('operation not permitted') || msg.contains('eperm')) {
        final cmd = [_sh(exeAbs), ...args.map(_sh)].join(' ');
        return await _runInLoginShell(cmd);
      }
      rethrow;
    }
  }

  // Resolve a ruta absoluta dun comando co login shell (command -v),
  // e con candidatos típicos (Homebrew/MacPorts/Python framework)
  // Resolve a ruta absoluta dun comando. En Windows usa `where`
  // (e tenta tamén nomes alternativos como gswin64c para Ghostscript).
  Future<String?> _which(String name) async {
    if (Platform.isWindows) {
      // --- PRIORIDADE: entorno micromamba se existe ---
      _initMmPathsIfNeeded();
      if (_mmEnvRoot != null) {
        String? fromEnv(String exeName) {
          final cands = <String>[
            p.join(_mmEnvRoot!, 'Library', 'bin', exeName),
            p.join(_mmEnvRoot!, 'Scripts', exeName),
            p.join(_mmEnvRoot!, exeName),
          ];
          for (final f in cands) {
            if (File(f).existsSync()) return f;
          }
          return null;
        }

        if (name.toLowerCase() == 'gs') {
          final alt = fromEnv('gswin64c.exe') ?? fromEnv('gswin32c.exe');
          if (alt != null) return alt;
        }
        final envExe = fromEnv('$name.exe') ?? fromEnv(name);
        if (envExe != null) return envExe;
      }

      final candidates = <String>[
        if (name.toLowerCase() == 'gs') 'gswin64c',
        name,
      ];

      // 1) where
      for (final n in candidates) {
        try {
          final r = await Process.run('where', [n], runInShell: true);
          if (r.exitCode == 0) {
            final out = (r.stdout as String).trim();
            if (out.isNotEmpty) {
              final first = out.split(RegExp(r'\r?\n')).first.trim();
              if (first.isNotEmpty && File(first).existsSync()) return first;
            }
          }
        } catch (_) {}
      }

      // 2) fallbacks típicos
      final env = Platform.environment;
      String? user = env['USERPROFILE'] ??
          ((env['HOMEDRIVE'] != null && env['HOMEPATH'] != null)
              ? '${env['HOMEDRIVE']}${env['HOMEPATH']}'
              : null);

      final extraDirs = <String>[
        r'C:\ProgramData\chocolatey\bin',
        if (env['SCOOP'] != null) p.join(env['SCOOP']!, 'shims'),
        if (user != null) p.join(user, 'scoop', 'shims'),
        r'C:\Program Files\Tesseract-OCR',
        r'C:\Program Files\gs\gs10.00.0\bin',
        r'C:\Program Files\gs\gs9.56.1\bin',
        if (user != null)
          p.join(user, r'AppData\Local\Programs\Python\Python312\Scripts'),
        if (user != null)
          p.join(user, r'AppData\Local\Programs\Python\Python311\Scripts'),
      ].whereType<String>().toList();

      for (final dir in extraDirs) {
        for (final n in candidates) {
          final exeNames = <String>['$n.exe', n];
          for (final exe in exeNames) {
            final full = p.join(dir, exe);
            if (File(full).existsSync()) return full;
          }
        }
      }
      return null;
    } else {
      final res = await _runInLoginShell('command -v ${_sh(name)} || true');
      if (res.exitCode == 0) {
        final out = (res.stdout as String).trim();
        if (out.isNotEmpty && out != name) return out;
      }
      const candidates = [
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/opt/local/bin',
        '/usr/bin',
        '/bin',
        '/Library/Frameworks/Python.framework/Versions/3.12/bin',
        '/Library/Frameworks/Python.framework/Versions/3.11/bin',
      ];
      for (final d in candidates) {
        final pth = '$d/$name';
        if (File(pth).existsSync()) return pth;
      }
      return null;
    }
  }

  void _initMmPathsIfNeeded() {
    if (!Platform.isWindows) return;
    final env = Platform.environment;
    final local = env['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return;
    _mmRoot ??= p.join(local, 'CIG', 'tools', 'mm');
    _mmBin ??= p.join(_mmRoot!, 'micromamba.exe');
    _mmEnvRoot ??= p.join(_mmRoot!, 'envs', 'ocr-env');
    _pythonExe ??= p.join(_mmEnvRoot!, 'python.exe');
  }

  // ===================== Resolver ferramentas e --version =====================

  Future<bool> _resolveToolsAndCheckVersions() async {
    _logAdd('Resolvendo rutas das ferramentas co PATH do usuario...');
    _tool['qpdf'] = (await _which('qpdf')) ?? '';
    _tool['ocrmypdf'] = (await _which('ocrmypdf')) ?? '';
    _tool['tesseract'] = (await _which('tesseract')) ?? '';
    _tool['gs'] = (await _which('gs')) ?? '';

    _logAdd(
        'qpdf      -> ${_tool['qpdf']!.isEmpty ? 'NON ATOPADO' : _tool['qpdf']}');
    _logAdd(
        'ocrmypdf  -> ${_tool['ocrmypdf']!.isEmpty ? 'NON ATOPADO' : _tool['ocrmypdf']}');
    _logAdd(
        'tesseract -> ${_tool['tesseract']!.isEmpty ? 'NON ATOPADO' : _tool['tesseract']}');
    _logAdd(
        'gs        -> ${_tool['gs']!.isEmpty ? 'NON ATOPADO' : _tool['gs']}');

    Future<bool> tryVersion(String key) async {
      final exe = _tool[key]!;
      if (exe.isEmpty) return false;
      try {
        final r = await _runWithFallback(exe, ['--version']);
        final first = (r.stdout is String ? r.stdout as String : '')
            .split('\n')
            .first
            .trim();
        _logAdd(
            '[$key --version] exit=${r.exitCode}${first.isNotEmpty ? ' · $first' : ''}');
        return r.exitCode == 0;
      } catch (e) {
        _logAdd('Erro lanzando $exe --version: $e');
        return false;
      }
    }

    final okQ = await tryVersion('qpdf');
    final okO = await tryVersion('ocrmypdf');
    await tryVersion('tesseract');
    await tryVersion('gs');

    final ok = okQ && okO;
    if (!ok) {
      if (Platform.isWindows) {
        _logAdd(
            'Ferramentas non listas. Intentando auto-instalación (micromamba)…');

        final local = Platform.environment['LOCALAPPDATA'] ?? '';
        if (local.isEmpty) {
          _logAdd('LOCALAPPDATA non dispoñible; non se pode usar micromamba.');
          return false;
        }

        try {
          final res = await bootstrapMicromambaAndEnv(
            localAppData: local,
            log: _logAdd,
          );

          // Actualiza rutas locais co resultado
          _mmRoot = res.mmRoot;
          _mmBin = res.mmBin;
          _mmEnvRoot = res.envRoot;
          _pythonExe = res.pythonExe;

          // Preferir ferramentas do entorno
          if (res.tools['qpdf'] != null) _tool['qpdf'] = res.tools['qpdf']!;
          if (res.tools['gs'] != null) _tool['gs'] = res.tools['gs']!;
          if (res.tools['tesseract'] != null)
            _tool['tesseract'] = res.tools['tesseract']!;
          // Para ocrmypdf: podería non existir .exe. Se non hai exe, usarase python -m no streaming.
          if (_tool['ocrmypdf']!.isEmpty && _pythonExe != null) {
            _tool['ocrmypdf'] = ''; // sinal para streaming con python -m
          }

          // Revalidación mínima
          final okQ2 = await tryVersion('qpdf');
          final okO2 = await _checkOcrmypdfVersionViaStreaming();
          final ok2 = okQ2 && okO2;
          if (!ok2) {
            _logAdd(
                'Ferramentas obrigatorias non listas (precísanse qpdf e ocrmypdf).');
          }
          return ok2;
        } catch (e, st) {
          _logAdd('Fallo no bootstrap micromamba: $e');
          _logAdd(st.toString());
        }
      }
      _logAdd(
          'Ferramentas obrigatorias non listas (precísanse qpdf e ocrmypdf).');
    }
    return ok;
  }

  Future<bool> _checkOcrmypdfVersionViaStreaming() async {
    try {
      final args = ['--version'];
      if (Platform.isWindows &&
          (_tool['ocrmypdf']?.isEmpty ?? true) &&
          _pythonExe != null) {
        final proc =
            await Process.start(_pythonExe!, ['-m', 'ocrmypdf', ...args]);
        proc.stdout.drain<void>();
        proc.stderr.drain<void>();
        final code = await proc.exitCode;
        return code == 0;
      } else if ((_tool['ocrmypdf'] ?? '').isNotEmpty) {
        final r = await _runWithFallback(_tool['ocrmypdf']!, args);
        return r.exitCode == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ============================== Execución proceso ==============================

  Future<ProcessResult> _run(String exeAbs, List<String> args) async {
    String realExe = exeAbs;
    if (!exeAbs.contains(Platform.pathSeparator) &&
        _tool.containsKey(exeAbs) &&
        (_tool[exeAbs]?.isNotEmpty ?? false)) {
      realExe = _tool[exeAbs]!;
    }
    try {
      return await Process.run(realExe, args);
    } on ProcessException catch (e) {
      final msg = (e.message).toLowerCase();
      if (!Platform.isWindows &&
          (msg.contains('operation not permitted') || msg.contains('eperm'))) {
        final cmd = [_sh(realExe), ...args.map(_sh)].join(' ');
        return await _runInLoginShell(cmd);
      }
      rethrow;
    }
  }

  // --- execución streaming de ocrmypdf (verbosa + heartbeat 30s) ---
  Future<bool> _runOcrmypdfStreaming(List<String> args) async {
    final useModule = Platform.isWindows &&
        (_tool['ocrmypdf']?.isEmpty ?? true) &&
        _pythonExe != null;

    final exe = useModule ? _pythonExe! : (_tool['ocrmypdf'] ?? '');
    if (exe.isEmpty) {
      _logAdd('Comando non resolto: ocrmypdf');
      return false;
    }

    final fullArgs = useModule ? ['-m', 'ocrmypdf', ...args] : args;
    _logAdd('Exec (stream): $exe ${fullArgs.join(' ')}');

    final env = Map<String, String>.from(Platform.environment)
      ..putIfAbsent('PYTHONUNBUFFERED', () => '1');

    Process? proc;
    try {
      proc = await Process.start(exe, fullArgs, environment: env);

      DateTime last = DateTime.now();
      final timer = Timer.periodic(const Duration(seconds: 30), (_) {
        final secs = DateTime.now().difference(last).inSeconds;
        if (secs >= 30) {
          _logAdd('… ocrmypdf segue traballando (${secs}s sen novas liñas) …');
        }
      });

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        last = DateTime.now();
        if (line.trim().isNotEmpty) _logAdd('[stdout ocrmypdf] $line');
      });

      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        last = DateTime.now();
        if (line.trim().isNotEmpty) _logAdd('[stderr ocrmypdf] $line');
      });

      final code = await proc.exitCode;
      timer.cancel();
      _logAdd('ocrmypdf -> exitCode $code');
      return code == 0;
    } catch (e) {
      _logAdd('Non se puido iniciar ocrmypdf en streaming: $e');
      try {
        proc?.kill();
      } catch (_) {}
      return false;
    }
  }

  // ============================== Utilidade modal ==============================

  void _endModal({bool ok = false}) {
    if (_activeCtrl == null) return;
    if (ok) {
      _activeCtrl!.finishOk();
    } else {
      _activeCtrl!.finishError();
    }
    _activeCtrl = null;
  }

  // ============================== Fluxo principal UI ==============================

  Future<void> _pickFiles() async {
    final typeGroup = XTypeGroup(label: 'PDFs', extensions: ['pdf']);
    final result = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (result.isEmpty) {
      _logAdd('Non se seleccionou ningún ficheiro.');
      return;
    }
    setState(() => _files.addAll(result.map((x) => File(x.path))));
    _logAdd('Engadidos ${result.length} PDF(s).');
  }

  Future<void> _generate() async {
    if (_files.isEmpty) {
      _logAdd('Lista baleira: arrastra PDFs ou preme Engadir.');
      return;
    }

    final ctrl = TaskProgressController();
    _activeCtrl = ctrl;
    // ignore: unawaited_futures
    showProgressLogDialog(context, ctrl, title: 'Xerando PDF…');
    await Future.delayed(const Duration(milliseconds: 16));

    try {
      final toolsOk = await _resolveToolsAndCheckVersions();
      if (!toolsOk) {
        _endModal(ok: false);
        return;
      }

      final int sum = _files.fold<int>(
          0, (s, f) => s + (f.existsSync() ? f.lengthSync() : 0));
      final int estimate = (sum * 1.2).toInt();
      _logAdd(
          'Estimación de tamaño tras OCR ~ ${_fmt(estimate)} (sumados ${_fmt(sum)}).');
      if (estimate > fourGB) {
        _logAdd('Estimación supera 4GB. Abortando.');
        _endModal(ok: false);
        return;
      }

      final location =
          await getSaveLocation(suggestedName: 'documento_final.pdf');
      if (location == null) {
        _logAdd('Cancelado polo usuario (non se escolleu destino).');
        _endModal(ok: false);
        return;
      }
      final savePath = location.path;

      setState(() {
        _busy = true;
        _progress = 0.01;
      });

      final swTotal = Stopwatch()..start();
      final tmp = await Directory.systemTemp.createTemp('pdfmerge_min_');
      final mergedRaw = p.join(tmp.path, 'merged_raw.pdf');
      final mergedFinal = p.join(tmp.path, 'merged_final.pdf');

      try {
        // 1) Merge con qpdf...
        setState(() => _progress = 0.2);
        final qpdfArgs = [
          '--empty',
          '--pages',
          ..._files.map((f) => f.path),
          '--',
          mergedRaw
        ];
        final sw = Stopwatch()..start();
        final result = await _run('qpdf', qpdfArgs);
        final okMerge = result.exitCode == 0;
        _logAdd('qpdf durou ${sw.elapsed}');

        if (!okMerge) {
          _logAdd('qpdf fallou. Abortando.');
          _endModal(ok: false);
          return;
        }

        // 2) Límite 4GB despois de unir
        final mSize = File(mergedRaw).lengthSync();
        _logAdd('Tamaño tras unión: ${_fmt(mSize)}');
        if (mSize > fourGB) {
          _logAdd('O unido supera 4GB. Abortando.');
          _endModal(ok: false);
          return;
        }

        // 3) OCR + PDF/A + 200 dpi con ocrmypdf ...
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
          '--skip-text',
          '--oversample',
          '200',
          '-v',
          '1',
          mergedRaw,
          mergedFinal,
        ];
        final sw2 = Stopwatch()..start();
        final okOcr = await _runOcrmypdfStreaming(ocrArgs);
        _logAdd('ocrmypdf durou ${sw2.elapsed}');
        if (!okOcr) {
          _logAdd('ocrmypdf fallou. Abortando.');
          _endModal(ok: false);
          return;
        }

        // 4) Límite final e gardar
        final fSize = File(mergedFinal).lengthSync();
        _logAdd('Tamaño final: ${_fmt(fSize)}');
        if (fSize > fourGB) {
          _logAdd('Resultado supera 4GB. Non se gardará.');
          _endModal(ok: false);
          return;
        }

        await File(mergedFinal).copy(savePath);
        _logAdd('Feito en ${swTotal.elapsed}. Gardado en: $savePath');
        _endModal(ok: true);
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
      }
    } finally {
      _endModal();
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
        title: const Text('Unir PDF [Resultado: OCR · PDF/A (200 dpi)]'),
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
                              'Arrastra aquí os PDF (podes reordenar)'),
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
                                  .where((f) =>
                                      f.path.toLowerCase().endsWith('.pdf'))
                                  .map((f) => File(f.path))));
                              //_logAdd('Arrastrados ${d.files.length} elemento(s).');
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color:
                                        _dragging ? Colors.blue : Colors.grey),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ReorderableListView.builder(
                                itemCount: _files.length,
                                onReorder: (o, n) {
                                  setState(() {
                                    if (n > o) n--;
                                    final it = _files.removeAt(o);
                                    _files.insert(n, it);
                                    // _logAdd('Reordenado $o -> $n');
                                  });
                                },
                                itemBuilder: (c, i) {
                                  final f = _files[i];
                                  final size =
                                      _fmt(f.existsSync() ? f.lengthSync() : 0);
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
                            controller: _logScroll,
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

// ======================== utilidade de modal bloqueante ========================

/// Estados posibles do proceso (para o modal)
enum TaskState { working, doneOk, doneError }

/// Controlador simple para enviar mensaxes ao modal e marcar cando remata.
class TaskProgressController {
  final ValueNotifier<String> log = ValueNotifier<String>('');
  final ValueNotifier<TaskState> state =
      ValueNotifier<TaskState>(TaskState.working);

  void append(String s) {
    final line = s.endsWith('\n') ? s : '$s\n';
    log.value = log.value + line;
  }

  void finishOk() {
    state.value = TaskState.doneOk;
  }

  void finishError() {
    state.value = TaskState.doneError;
  }

  void reset() {
    log.value = '';
    state.value = TaskState.working;
  }
}

Future<void> showProgressLogDialog(
  BuildContext context,
  TaskProgressController controller, {
  String title = 'Procesando…',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Progreso',
    barrierColor: Colors.black.withValues(alpha: 0.6),
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
                    child: Text(widget.title,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
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
                              fontFamily: 'monospace', height: 1.3),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
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
