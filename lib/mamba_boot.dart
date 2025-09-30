// lib/mamba_boot.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Resultado do bootstrap: rutas resoltas e python do entorno
class MambaBootstrapResult {
  final String mmRoot;
  final String mmBin;
  final String envRoot;
  final String? pythonExe; // ...\envs\ocr-env\python.exe (ou null se fallou)
  final Map<String, String> tools; // qpdf, gs, tesseract (se atopados)

  MambaBootstrapResult({
    required this.mmRoot,
    required this.mmBin,
    required this.envRoot,
    required this.pythonExe,
    required this.tools,
  });
}

/// Detecta a arquitectura real do Windows para escoller o binario correcto de micromamba:
///  - 'win-arm64' se o SO é Arm64
///  - 'win-64'   se o SO é x64
///  - 'win-32'   noutro caso
String _winMicromambaTag(void Function(String) log) {
  if (!Platform.isWindows) return 'win-64';

  final env = Platform.environment;
  String arch = (env['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
  String wow = (env['PROCESSOR_ARCHITEW6432'] ?? '').toLowerCase();
  String id = (env['PROCESSOR_IDENTIFIER'] ?? '').toLowerCase();

  if (arch.contains('arm64') || wow.contains('arm64') || id.contains('arm')) {
    return 'win-arm64';
  }
  final is64 = arch.contains('amd64') ||
      arch.contains('x86_64') ||
      wow.contains('amd64') ||
      wow.contains('x86_64');
  if (is64) return 'win-64';

  try {
    final ps = [
      'powershell',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'[Console]::OutputEncoding=[Text.UTF8Encoding]::UTF8; ' +
          r'$os=[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture; ' +
          r'$pa=[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture; ' +
          r'Write-Output "OS=$os"; Write-Output "PROC=$pa";'
    ];
    final res = Process.runSync(ps.first, ps.sublist(1), runInShell: true);
    if (res.exitCode == 0) {
      final out =
          (res.stdout is String ? res.stdout as String : '').toLowerCase();
      if (out.contains('os=arm64')) return 'win-arm64';
      if (out.contains('os=x64')) return 'win-64';
      if (out.contains('os=x86')) return 'win-32';
    }
  } catch (_) {}
  if (arch.contains('arm') || wow.contains('arm') || id.contains('arm')) {
    return 'win-arm64';
  }
  return 'win-64';
}

bool _looksLikeExe(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return false;
    final raf = f.openSync();
    final sig = raf.readSync(2);
    raf.closeSync();
    // 'M''Z'
    return sig.length == 2 && sig[0] == 0x4D && sig[1] == 0x5A;
  } catch (_) {
    return false;
  }
}

/// Descarga de forma robusta (PS -> curl -> HttpClient validado -> HttpClient relaxado)
Future<File> _downloadFile(
    String url, String destPath, void Function(String) log) async {
  final dest = File(destPath);
  await dest.parent.create(recursive: true);

  if (Platform.isWindows) {
    // PowerShell (TLS1.2 + fallback a BITS)
    try {
      log('Tentando descarga con PowerShell (TLS1.2 + BITS)…');
      final safeUrl = url.replaceAll('"', '""');
      final safeOut = destPath.replaceAll('"', '""');

      final psScript = r'''
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
  Invoke-WebRequest -UseBasicParsing -Uri "{{URL}}" -OutFile "{{OUT}}"
  exit 0
} catch {
  try {
    Import-Module BitsTransfer -ErrorAction SilentlyContinue | Out-Null
    Start-BitsTransfer -Source "{{URL}}" -Destination "{{OUT}}"
    exit 0
  } catch {
    Write-Error $_
    exit 1
  }
}
'''
          .replaceAll('{{URL}}', safeUrl)
          .replaceAll('{{OUT}}', safeOut);

      final psCmd = [
        'powershell',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        psScript.replaceAll(r'$_', r'\$_'),
      ];
      final proc =
          await Process.run(psCmd.first, psCmd.sublist(1), runInShell: true);
      if (proc.exitCode == 0 && dest.existsSync() && dest.lengthSync() > 0) {
        log('Descarga completada con PowerShell.');
        return dest;
      }
      log('PowerShell fallou (exit ${proc.exitCode}).');
    } catch (e) {
      log('PowerShell non dispoñible ou erro: $e');
    }

    // curl
    try {
      log('Tentando descarga con curl…');
      final proc = await Process.run('curl', ['-L', '-o', destPath, url],
          runInShell: true);
      if (proc.exitCode == 0 && dest.existsSync() && dest.lengthSync() > 0) {
        log('Descarga completada con curl.');
        return dest;
      }
      log('curl fallou (exit ${proc.exitCode}).');
    } catch (e) {
      log('curl non dispoñible ou erro: $e');
    }
  }

  // HttpClient validado
  try {
    log('Tentando descarga con HttpClient (TLS validado)…');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode == 200) {
      final sink = dest.openWrite();
      await res.forEach(sink.add);
      await sink.close();
      if (dest.existsSync() && dest.lengthSync() > 0) {
        log('Descarga completada con HttpClient (validado).');
        return dest;
      }
    }
    log('HttpClient standard fallou (HTTP ${res.statusCode}).');
  } catch (e) {
    log('HttpClient standard erro: $e');
  }

  // HttpClient relaxado (só para o host exacto)
  try {
    final uri = Uri.parse(url);
    log('Tentando descarga con HttpClient relaxado para host ${uri.host} (⚠️ coidado).');
    final ctx = SecurityContext.defaultContext;
    final client = HttpClient(context: ctx)
      ..badCertificateCallback = (cert, host, port) => host == uri.host;
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final sink = dest.openWrite();
    await res.forEach(sink.add);
    await sink.close();
    if (dest.existsSync() && dest.lengthSync() > 0) {
      log('Descarga completada con HttpClient (relaxado).');
      return dest;
    }
    throw Exception('Descarga baleira');
  } catch (e) {
    log('HttpClient relaxado tamén fallou: $e');
    throw Exception('Non se puido descargar $url');
  }
}

Future<int> _runExeStreaming(
    String exe, List<String> args, void Function(String) log,
    {String? workDir}) async {
  log('Exec EXE: $exe ${args.join(' ')}');
  final proc = await Process.start(
    exe,
    args,
    workingDirectory: workDir,
    runInShell: false,
  );
  proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) {
    if (l.trim().isNotEmpty) log('[stdout] $l');
  });
  proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) {
    if (l.trim().isNotEmpty) log('[stderr] $l');
  });
  final code = await proc.exitCode;
  log('EXE -> exitCode $code');
  return code;
}

Future<String?> _installMicromambaViaPS(void Function(String) log) async {
  try {
    log('Instalando micromamba con install.ps1 (oficial)…');
    final ps = [
      'powershell',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ' +
          r'Invoke-Expression ((Invoke-WebRequest -UseBasicParsing -Uri https://micro.mamba.pm/install.ps1).Content); ' +
          r'$p = Join-Path $Env:LocalAppData "micromamba\micromamba.exe"; ' +
          r'Write-Output $p'
    ];
    final res = await Process.run(ps.first, ps.sublist(1), runInShell: true);
    final out = (res.stdout is String ? res.stdout as String : '').trim();
    if (res.exitCode == 0 && out.isNotEmpty && File(out).existsSync()) {
      log('micromamba instalado en: $out');
      return out;
    }
    log('install.ps1 fallou (exit ${res.exitCode}). stdout="$out"');
  } catch (e) {
    log('Erro lanzando install.ps1: $e');
  }
  return null;
}

/// Bootstrap completo en Windows:
/// - decide rutas base (mmRoot, mmBin, envRoot)
/// - tenta obter un micromamba.exe válido (install.ps1 => API tags en cascada)
/// - crea o entorno ocr-env se falta
/// - devolve rutas resoltas de qpdf/gs/tesseract e o python.exe do entorno
Future<MambaBootstrapResult> bootstrapMicromambaAndEnv({
  required String localAppData,
  required void Function(String) log,
}) async {
  if (!Platform.isWindows) {
    throw StateError('Só Windows soportado para micromamba bootstrap');
  }

  final mmRoot = p.join(localAppData, 'CIG', 'tools', 'mm');
  final mmBin = p.join(mmRoot, 'micromamba.exe');
  final envRoot = p.join(mmRoot, 'envs', 'ocr-env');
  final pythonExe = p.join(envRoot, 'python.exe');

  await Directory(mmRoot).create(recursive: true);

  // 1) micromamba.exe válido
  String tagPrimary = _winMicromambaTag(log);
  log('Arquitectura Windows detectada: $tagPrimary');

  bool needDownload = !File(mmBin).existsSync();
  if (!needDownload) {
    try {
      final r = await Process.run(mmBin, ['--version']);
      if (r.exitCode != 0) needDownload = true;
    } on ProcessException catch (e) {
      final msg = (e.message).toLowerCase();
      if (msg.contains('not a valid win32') ||
          msg.contains('no es compatible') ||
          msg.contains('not compatible')) {
        needDownload = true;
      } else {
        needDownload = true;
      }
    }
  }

  if (needDownload) {
    final psPath = await _installMicromambaViaPS(log);
    if (psPath != null && _looksLikeExe(psPath)) {
      await File(psPath).copy(mmBin);
      log('Copiado micromamba desde install.ps1 a: $mmBin');
    } else {
      final tags = <String>[tagPrimary, 'win-64', 'win-32'].toSet().toList();
      try {
        if (File(mmBin).existsSync()) await File(mmBin).delete();
      } catch (_) {}
      bool got = false;
      for (final tag in tags) {
        final url = 'https://micro.mamba.pm/api/micromamba/$tag/latest';
        log('Descargando micromamba.exe ($tag)…');
        try {
          await _downloadFile(url, mmBin, log);
          if (_looksLikeExe(mmBin)) {
            log('micromamba.exe descargado correcto ($tag).');
            got = true;
            break;
          } else {
            log('Descarga non é EXE (posible JSON). Tentando outro tag…');
          }
        } catch (e) {
          log('Erro descargando $tag: $e');
        }
      }
      if (!got) {
        throw Exception('Non se puido obter micromamba compatible.');
      }
    }

    // Verificación post-descarga
    try {
      final r = await Process.run(mmBin, ['--version']);
      if (r.exitCode != 0) {
        log('micromamba recén descargado devolveu exit ${r.exitCode}.');
      } else {
        final first = (r.stdout is String ? (r.stdout as String) : '')
            .split('\n')
            .first
            .trim();
        if (first.isNotEmpty) log('[micromamba --version] $first');
      }
    } catch (e) {
      log('Erro ao verificar micromamba recén descargado: $e');
    }
  } else {
    log('micromamba.exe xa existe en: $mmBin');
  }

  // 2) crear entorno se falta python.exe
  if (!File(pythonExe).existsSync()) {
    log('Creando entorno con ocrmypdf, qpdf, ghostscript, tesseract…');
    final args = [
      'create',
      '-y',
      '-r',
      mmRoot,
      '-n',
      'ocr-env',
      '-c',
      'conda-forge',
      'ocrmypdf',
      'qpdf',
      'ghostscript',
      'tesseract',
    ];
    final code = await _runExeStreaming(mmBin, args, log);
    if (code != 0) {
      throw Exception('Erro creando entorno micromamba (exit $code)');
    }
  } else {
    log('Entorno ocr-env xa existe.');
  }

  // 3) Resolver binarios dentro do entorno
  String? findInEnv(List<String> rels) {
    for (final r in rels) {
      final full = p.isAbsolute(r) ? r : p.join(envRoot, r);
      if (File(full).existsSync()) return full;
    }
    return null;
  }

  final tools = <String, String>{};
  final qpdfExe = findInEnv([
    p.join('Library', 'bin', 'qpdf.exe'),
    p.join('Scripts', 'qpdf.exe'),
    'qpdf.exe',
  ]);
  final gsExe = findInEnv([
    p.join('Library', 'bin', 'gswin64c.exe'),
    p.join('Library', 'bin', 'gswin32c.exe'),
    'gswin64c.exe',
    'gswin32c.exe',
  ]);
  final tessExe = findInEnv([
    p.join('Library', 'bin', 'tesseract.exe'),
    'tesseract.exe',
  ]);

  if (qpdfExe != null) tools['qpdf'] = qpdfExe;
  if (gsExe != null) tools['gs'] = gsExe;
  if (tessExe != null) tools['tesseract'] = tessExe;

  return MambaBootstrapResult(
    mmRoot: mmRoot,
    mmBin: mmBin,
    envRoot: envRoot,
    pythonExe: File(pythonExe).existsSync() ? pythonExe : null,
    tools: tools,
  );
}
