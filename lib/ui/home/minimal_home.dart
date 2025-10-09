// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'dart:async'; // engadido para streaming ocrmypdf
import 'dart:convert'; // engadido para decodificar stdout/stderr liña a liña

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_merger_ocr_pdfa/constants.dart';

import '../widgets/progress_log_dialog.dart';
import '../widgets/success_result_dialog.dart';

import '../../models/app_settings.dart';
import '../../services/app_settings_store.dart';
import '../pages/settings_page.dart';

// actualizador
import '../../services/update_service.dart';

import 'package:package_info_plus/package_info_plus.dart';


class MinimalHome extends StatefulWidget {
  const MinimalHome({super.key});
  @override
  State<MinimalHome> createState() => _MinimalHomeState();
}

class _MinimalHomeState extends State<MinimalHome> {
  String? _successPath;
  int _successSize = 0;
  int _successPages = 0;
  bool _successPdfaLikely = false;
  Future<void>? _genDialogFuture;
  bool _showSuccessOnGenClose = false;
  final List<File> _files = [];
  bool _dragging = false;
  bool _busy = false;
  double _progress = 0.0;
  String _log = '';
  // --- [MODAL LOG - engadido] controlador do modal activo (se existe) ---
  TaskProgressController? _activeCtrl;

  static const int fourGB = 4 * 1024 * 1024 * 1024; // 4 GiB

  // timer para update
  Timer? _updateTimer;

  String? version;

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version; // ou '${info.version}+${info.buildNumber}'
    });
  }



  // --- Bundled tools (Windows) ---
  // ignore: unused_field
  String? _bundleDir;         // base: <exeDir>\OCRmyPDFPortable
  String? _bundleOcrmypdf;    // <base>\OCRmyPDFPortable.exe
  String? _bundleQpdf;        // <base>\OCRmyPDFPortable\_internal\vendors\qpdf\qpdf.exe
  String? _bundleGs;          // <base>\OCRmyPDFPortable\_internal\vendors\ghostscript\bin\gswin64c.exe
  String? _bundleTesseract;   // <base>\OCRmyPDFPortable\_internal\vendors\tesseract\tesseract.exe
  final Map<String, String> _bundleEnv = {}; // PATH/TESSDATA_PREFIX

  // rutas resoltas das ferramentas
  final Map<String, String> _tool = {
    'qpdf': '',
    'ocrmypdf': '',
    'tesseract': '',
    'gs': '',
  };

  // Autoscroll Log
  late final ScrollController _logScroll;

  final _settingsStore = AppSettingsStore();
  AppSettings _settings = const AppSettings();


  @override
  void initState() {
    super.initState();
    _logScroll = ScrollController();
    _settingsStore.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });

    _loadVersion();

    // Comproba unha vez aos 2s do arranque
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        checkForUpdates(context, manifestUrl: kAppcastUrl);
      }
    });
    // E cada 6 horas
    _updateTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (mounted) {
        checkForUpdates(context, manifestUrl: kAppcastUrl);
      }
    });
  }


  @override
  void dispose() {
    _updateTimer?.cancel();

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
        // Se prefires suave: _logScroll.animateTo(...);
      }
    });
  }

  // ========================= Helpers PATH/login shell & exec =========================
  // Executa unha orde no shell de login real do usuario en Unix
  // e en Windows usa cmd.exe /C (non existe zsh nin -lc).
  Future<ProcessResult> _runInLoginShell(String commandLine) {
    if (Platform.isWindows) {
      // En Windows, deixa que cmd.exe resolva o PATH do usuario
      return Process.run('cmd.exe', ['/C', commandLine]);
    } else {
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      return Process.run(shell, ['-lc', commandLine]);
    }
  }

  String _sh(String s) => "'${s.replaceAll("'", r"'\\''")}'";

  // Fallback robusto: intenta exec directo; se falla por EPERM, executa vía login shell
  // ignore: unused_element
  Future<ProcessResult> _runWithFallback(
      String exeAbs, List<String> args) async {
    try {
      return await Process.run(exeAbs, args, environment: _envWithBundle());
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

  // ---------- Bundled helpers (Windows) ----------
  String _exeDir() => p.dirname(Platform.resolvedExecutable);

  String _detectBundleDir() {
    final exeDir = _exeDir();
    final d1 = p.join(exeDir, 'OCRmyPDFPortable');
    if (Directory(d1).existsSync()) return d1;
    final d2 = p.join(Directory.current.path, 'OCRmyPDFPortable');
    if (Directory(d2).existsSync()) return d2;
    return exeDir;
  }

  void _setupBundledToolsIfPresent() {
    if (!Platform.isWindows) return;

    final base = _detectBundleDir();
    _bundleDir = base;

    String pathOf(String rel) => p.join(base, rel);
    final vroot =
        'OCRmyPDFPortable${Platform.pathSeparator}_internal${Platform.pathSeparator}vendors';

    _bundleOcrmypdf = pathOf('OCRmyPDFPortable.exe');
    _bundleQpdf = pathOf(
        '$vroot${Platform.pathSeparator}qpdf${Platform.pathSeparator}qpdf.exe');
    _bundleGs = pathOf(
        '$vroot${Platform.pathSeparator}ghostscript${Platform.pathSeparator}bin${Platform.pathSeparator}gswin64c.exe');
    if (!File(_bundleGs!).existsSync()) {
      _bundleGs = pathOf(
          '$vroot${Platform.pathSeparator}ghostscript${Platform.pathSeparator}bin${Platform.pathSeparator}gswin32c.exe');
    }
    _bundleTesseract = pathOf(
        '$vroot${Platform.pathSeparator}tesseract${Platform.pathSeparator}tesseract.exe');

    if (File(_bundleQpdf ?? '').existsSync()) _tool['qpdf'] = _bundleQpdf!;
    if (File(_bundleGs ?? '').existsSync()) _tool['gs'] = _bundleGs!;
    if (File(_bundleTesseract ?? '').existsSync()) {
      _tool['tesseract'] = _bundleTesseract!;
    }
    if (File(_bundleOcrmypdf ?? '').existsSync()) {
      _tool['ocrmypdf'] = _bundleOcrmypdf!;
    }

    final pathParts = <String>[];
    String dirOf(String f) => p.dirname(f);

    if (_bundleQpdf != null && File(_bundleQpdf!).existsSync()) {
      pathParts.add(dirOf(_bundleQpdf!));
    }
    if (_bundleGs != null && File(_bundleGs!).existsSync()) {
      pathParts.add(dirOf(_bundleGs!));
    }
    if (_bundleTesseract != null && File(_bundleTesseract!).existsSync()) {
      pathParts.add(dirOf(_bundleTesseract!));
    }
    if (_bundleOcrmypdf != null && File(_bundleOcrmypdf!).existsSync()) {
      pathParts.add(dirOf(_bundleOcrmypdf!));
    }

    final tessdataDir = pathOf(
        '$vroot${Platform.pathSeparator}tesseract${Platform.pathSeparator}tessdata');
    if (Directory(tessdataDir).existsSync()) {
      _bundleEnv['TESSDATA_PREFIX'] =
          p.normalize(pathOf('$vroot${Platform.pathSeparator}tesseract'));
    }

    final sep = Platform.isWindows ? ';' : ':';
    final currentPath = Platform.environment['PATH'] ?? '';
    final prepend = pathParts.toSet().join(sep);
    if (prepend.isNotEmpty) {
      _bundleEnv['PATH'] =
          prepend + (currentPath.isEmpty ? '' : '$sep$currentPath');
    }
  }

  Map<String, String> _envWithBundle() {
    final e = Map<String, String>.from(Platform.environment);
    _bundleEnv.forEach((k, v) => e[k] = v);
    return e;
  }
  // -----------------------------------------------

  // Se existe o cartafol OCRmyPDFPortable ao lado do .exe, devolve a súa ruta
  String? _portableRootWindows() {
    final exeDir = _winExeDir();
    final root = p.join(exeDir, 'OCRmyPDFPortable');
    if (Directory(root).existsSync()) return root;
    return null;
  }


  // Resolve a ruta absoluta dun comando co login shell (command -v),
  // e con candidatos típicos (Homebrew/MacPorts/Python framework)
  // Resolve a ruta absoluta dun comando. En Windows usa `where`
  // (e tenta tamén nomes alternativos como gswin64c para Ghostscript).
  Future<String?> _which(String name) async {
    if (Platform.isWindows) {
      // Algúns binarios teñen nomes diferentes en Windows.
      final candidates = <String>[
        if (name.toLowerCase() == 'gs') 'gswin64c', // Ghostscript
        name,
      ];

      // --- PRIORIDADE: OCRmyPDFPortable autocontido ---
      final pr = _portableRootWindows();
      if (pr != null) {
        // exe principal de OCRmyPDFPortable
        final portableExe = p.join(pr, 'OCRmyPDFPortable.exe');

        // vendors internos
        final vRoot = p.join(pr, 'OCRmyPDFPortable', '_internal', 'vendors');

        String? fromVendorsQpdf() =>
            File(p.join(vRoot, 'qpdf', 'qpdf.exe')).existsSync()
                ? p.join(vRoot, 'qpdf', 'qpdf.exe')
                : null;

        String? fromVendorsGs() {
          final a = p.join(vRoot, 'ghostscript', 'bin', 'gswin64c.exe');
          final b = p.join(vRoot, 'ghostscript', 'bin', 'gswin32c.exe');
          if (File(a).existsSync()) return a;
          if (File(b).existsSync()) return b;
          return null;
        }

        String? fromVendorsTess() =>
            File(p.join(vRoot, 'tesseract', 'tesseract.exe')).existsSync()
                ? p.join(vRoot, 'tesseract', 'tesseract.exe')
                : null;

        switch (name.toLowerCase()) {
          case 'ocrmypdf':
            if (File(portableExe).existsSync()) return portableExe;
            break;
          case 'qpdf':
            final q = fromVendorsQpdf();
            if (q != null) return q;
            break;
          case 'gs':
            final g = fromVendorsGs();
            if (g != null) return g;
            break;
          case 'tesseract':
            final t = fromVendorsTess();
            if (t != null) return t;
            break;
        }
      }
      // --- FIN PRIORIDADE OCRmyPDFPortable ---


      // 1) Proba con `where` (respecta o PATH real do usuario).
      for (final n in candidates) {
        try {
          final r = await Process.run('where', [n], runInShell: true);
          if (r.exitCode == 0) {
            final out = (r.stdout as String).trim();
            if (out.isNotEmpty) {
              // colle a primeira ruta válida
              final first = out.split(RegExp(r'\r?\n')).first.trim();
              if (first.isNotEmpty && File(first).existsSync()) return first;
            }
          }
        } catch (_) {
          // Ignora, tentamos fallbacks
        }
      }

      // 2) Pequenos fallbacks típicos (chocolatey/scoop/Python scripts)
      final env = Platform.environment;
      String? user = env['USERPROFILE'] ??
          ((env['HOMEDRIVE'] != null && env['HOMEPATH'] != null)
              ? '${env['HOMEDRIVE']}${env['HOMEPATH']}'
              : null)

      ;

      final extraDirs = <String>[
        r'C:\ProgramData\chocolatey\bin',
        // Scoop
        if (env['SCOOP'] != null) p.join(env['SCOOP']!, 'shims'),
        if (user != null) p.join(user, 'scoop', 'shims'),
        // Tesseract típico
        r'C:\Program Files\Tesseract-OCR',
        // Ghostscript típico
        r'C:\Program Files\gs\gs10.00.0\bin',
        r'C:\Program Files\gs\gs9.56.1\bin',
        // Python Scripts do usuario
        if (user != null)
          p.join(user, r'AppData\Local\Programs\Python\Python312\Scripts'),
        if (user != null)
          p.join(user, r'AppData\Local\Programs\Python\Python311\Scripts'),
      ].whereType<String>().toList();

      for (final dir in extraDirs) {
        for (final n in candidates) {
          final exeNames = <String>['$n.exe', n]; // por se viñese xa con .exe
          for (final exe in exeNames) {
            final full = p.join(dir, exe);
            if (File(full).existsSync()) return full;
          }
        }
      }

      return null;
    } else {
      // Unix/macOS: usa o shell de login para obter PATH real do usuario
      final res = await _runInLoginShell('command -v ${_sh(name)} || true');
      if (res.exitCode == 0) {
        final out = (res.stdout as String).trim();
        if (out.isNotEmpty && out != name) return out;
      }
      const candidates = [
        '/opt/homebrew/bin', // Apple Silicon (Homebrew)
        '/usr/local/bin', // Intel (Homebrew)
        '/opt/local/bin', // MacPorts
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
  }

  // ===================== Resolver ferramentas e --version =====================

  // Ruta do .exe (runner) en Windows (Debug/Release)
  String _winExeDir() => p.dirname(Platform.resolvedExecutable);

  // Constrúe os paths PORTABLE obrigatorios (xunto ao .exe)
  Map<String, String> _portableToolPathsWindows() {
    final exeDir = _winExeDir();
    final root = p.join(exeDir, 'OCRmyPDFPortable');
    return {
      'ocrmypdf': p.join(root, 'OCRmyPDFPortable.exe'),
      'qpdf': p.join(root, '_internal', 'vendors', 'qpdf', 'qpdf.exe'),
      'tesseract': p.join(root, '_internal', 'vendors', 'tesseract', 'tesseract.exe'),
      'gs': p.join(root, '_internal', 'vendors', 'ghostscript', 'bin', 'gswin64c.exe'),
    };
  }


  Future<bool> _resolveToolsAndCheckVersions() async {
    if (Platform.isWindows) {
      // Forzar rutas PORTABLE (sen buscar no sistema)
      final forced = _portableToolPathsWindows();
      _tool['qpdf'] = forced['qpdf']!;
      _tool['ocrmypdf'] = forced['ocrmypdf']!;
      _tool['tesseract'] = forced['tesseract']!;
      _tool['gs'] = forced['gs']!;
      // Configurar PATH/TESSDATA_PREFIX para o bundle
      _setupBundledToolsIfPresent();
    } else {
      _logAdd('Resolvendo rutas das ferramentas co PATH do usuario...');
      _tool['qpdf'] = (await _which('qpdf')) ?? '';
      _tool['ocrmypdf'] = (await _which('ocrmypdf')) ?? '';
      _tool['tesseract'] = (await _which('tesseract')) ?? '';
      _tool['gs'] = (await _which('gs')) ?? '';
    }

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
        final r =
            await Process.run(exe, ['--version'], environment: _envWithBundle());
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
    final okO = await tryVersion('ocrmypdf'); // importante co Portable
    await tryVersion('tesseract'); // informativos
    await tryVersion('gs');

    final ok = okQ && okO;
    if (!ok) {
      _logAdd(
          'Ferramentas obrigatorias non listas (precísanse qpdf e ocrmypdf).');
    }
    return ok;
  }

  // ============================== Execución proceso ==============================

  Future<int> _getPageCount(String pdfPath) async {
    try {
      final r = await _run('qpdf', ['--show-npages', pdfPath]);
      if (r.exitCode == 0) {
        final s = (r.stdout is String ? r.stdout as String : '').trim();
        final n = int.tryParse(s);
        return n ?? 0;
      }
    } catch (_) {}
    return 0;
  }


  Future<ProcessResult> _run(String exeAbs, List<String> args) async {
    // Bridge: se nos pasan 'qpdf'/'gs'/... e temos ruta en _tool, úsaa.
    String realExe = exeAbs;
    if (!exeAbs.contains(Platform.pathSeparator) &&
        _tool.containsKey(exeAbs) &&
        (_tool[exeAbs]?.isNotEmpty ?? false)) {
      realExe = _tool[exeAbs]!;
    }
    try {
      return await Process.run(realExe, args, environment: _envWithBundle());
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

  // --- NOVO: execución streaming de ocrmypdf (verbosa + heartbeat 30s) ---
  Future<bool> _runOcrmypdfStreaming(List<String> args) async {
    // En Windows, usa o exe do bundle; en macOS/Linux usa o que haxa en PATH/_tool
    final exe = (_tool['ocrmypdf'] ?? '');
    if (exe.isEmpty) {
      _logAdd('Comando non resolto: ocrmypdf');
      return false;
    }

    _logAdd('Exec (stream): $exe ${args.join(' ')}');

    Process? proc;
    try {
      proc = await Process.start(exe, args, environment: _envWithBundle());

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
          if (line.trim().isNotEmpty && _settings.logStdout) {
            _logAdd('[stdout ocrmypdf] $line');
          }
      });

      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        last = DateTime.now();
          if (line.trim().isNotEmpty && _settings.logStderr) {
            _logAdd('[stderr ocrmypdf] $line');
          }
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
    //_logAdd('Abrindo diálogo para seleccionar PDFs...');
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
    //_logAdd('--- PREMEU "Xerar PDF" ---');
    if (_files.isEmpty) {
      _logAdd('Lista baleira: arrastra PDFs ou preme Engadir.');
      return;
    }

    // Mostrar modal de inmediato
    final ctrl = TaskProgressController();
    _activeCtrl = ctrl;
    // ignore: unawaited_futures
    _genDialogFuture = showProgressLogDialog(context, ctrl, title: 'Xerando PDF…');
    _genDialogFuture!.then((_) async {
      if (_showSuccessOnGenClose && _successPath != null) {
        await showSuccessResultDialog(
          context,
          savePath: _successPath!,
          sizeBytes: _successSize,
          pageCount: _successPages,
          pdfaLikely: _successPdfaLikely,
        );
        setState(() {
          _files.clear();              // SEMPRE se limpa a lista
          if (!_settings.preserveLog) {
            _log = '';                 // ← só se limpa o Log se NON está marcado conservar
          }
          _progress = 0.0;
          _busy = false;
          _dragging = false;
        });
        _showSuccessOnGenClose = false;
      }
    });

    await Future.delayed(
        const Duration(milliseconds: 16)); // dar un frame para pintar o modal

    try {
      // 0) resolver rutas e validar --version
      final toolsOk = await _resolveToolsAndCheckVersions();
      if (!toolsOk) {
        _endModal(ok: false); // <- habilitar botón Pechar e parar spinner
        return;
      }

      // Estimación (suma * 1.2)
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
        final List<String> qpdfArgs = [
          ..._settings.buildQpdfWarnArgs(),
          '--empty',
          '--pages',
          ..._files.map((f) => f.path),
          '--',
          mergedRaw
        ];
        final extraQ = _settings.parseFreeArgs(_settings.extraQpdfArgs);
        qpdfArgs.insertAll(0, extraQ);

        // _logAdd('CMD: qpdf ${qpdfArgs.join(' ')}');
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
        final ocrArgs = <String>[
          '--output-type', 'pdfa',
          '--optimize', '3',
          '--pdfa-image-compression', 'lossless',
          '--jobs', Platform.numberOfProcessors.toString(),
          ..._settings.buildOcrmypdfModeArgs(), // (--skip-text | --redo-ocr)
          '--oversample', '200',
          '-v', _settings.ocrmypdfVerbosity.toString(),
          ..._settings.parseFreeArgs(_settings.extraOcrmypdfArgs),
          mergedRaw,
          mergedFinal,
        ];

        // _logAdd('CMD: ocrmypdf ${ocrArgs.join(' ')}');
        final sw2 = Stopwatch()..start();
        final okOcr =
            await _runOcrmypdfStreaming(ocrArgs); // engadido (streaming)
        _logAdd('ocrmypdf durou ${sw2.elapsed}');
        if (!okOcr) {
          _logAdd('ocrmypdf fallou. Abortando.');
          _endModal(ok: false);
          return;
        }

        // 4) Límite final e gardar
        final fSize = File(mergedFinal).lengthSync();
        final pages = await _getPageCount(mergedFinal);
        _logAdd('Tamaño final: ${_fmt(fSize)}');
        if (fSize > fourGB) {
          _logAdd('Resultado supera 4GB. Non se gardará.');
          _endModal(ok: false);
          return;
        }

        await File(mergedFinal).copy(savePath);
        _successPath = savePath;
        _successSize = fSize;
        _successPages = pages;
        _successPdfaLikely = true;
        _logAdd('Feito en ${swTotal.elapsed}. Gardado en: $savePath');
        _showSuccessOnGenClose = true;
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
      // En calquera caso, se non se pechou xa, pecha a modal
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
        actions: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Axustes',
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  if (changed == true) {
                    final s = await _settingsStore.load();
                    if (mounted) setState(() => _settings = s);
                  }
                },
              ),
              if (version != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'v$version',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ],

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
                                    //  _logAdd('Reordenado $o -> $n');
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
                                          : () => setState(() {
                                              final removed = _files.removeAt(i);
                                              _logAdd("Eliminado ficheiro: ${p.basename(removed.path)}");
                                            }),
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
                  child: Card
                  (
                    margin: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ListTile(dense: true, title: Text('Log')),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _logScroll, // <-- AUTOSCROLL LOG
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
