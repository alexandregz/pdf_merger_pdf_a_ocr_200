import 'package:flutter/foundation.dart';

enum OCRMode { skipText, redoOCR }
enum QpdfWarnMode { normal, warningExit0, noWarn }

@immutable
class AppSettings {
  final OCRMode ocrMode;               // (--skip-text | --redo-ocr)
  final int ocrmypdfVerbosity;         // -v <n>
  final String extraOcrmypdfArgs;      // argumentos extra libres
  final QpdfWarnMode qpdfWarnMode;     // --warning-exit-0 | --no-warn | normal
  final String extraQpdfArgs;          // argumentos extra libres para qpdf
  final bool preserveLog;              // preserva logs ao finalizar e so limpa lista de arquivos na ventana principal
  final bool logStdout;                // stdout ocrmypdf
  final bool logStderr;                // stderr ocrmypdf

  const AppSettings({
    this.ocrMode = OCRMode.skipText,
    this.ocrmypdfVerbosity = 1,
    this.extraOcrmypdfArgs = '',
    this.qpdfWarnMode = QpdfWarnMode.normal,
    this.extraQpdfArgs = '',
    this.preserveLog = false,
    this.logStdout = true,   // por defecto activado
    this.logStderr = true,   // para primeiras versions empregadas por users saco todo output, despois a quitar
  });

  AppSettings copyWith({
    OCRMode? ocrMode,
    int? ocrmypdfVerbosity,
    String? extraOcrmypdfArgs,
    QpdfWarnMode? qpdfWarnMode,
    String? extraQpdfArgs,
    bool? preserveLog,
    bool? logStdout,
    bool? logStderr,
  }) {
    return AppSettings(
      ocrMode: ocrMode ?? this.ocrMode,
      ocrmypdfVerbosity: ocrmypdfVerbosity ?? this.ocrmypdfVerbosity,
      extraOcrmypdfArgs: extraOcrmypdfArgs ?? this.extraOcrmypdfArgs,
      qpdfWarnMode: qpdfWarnMode ?? this.qpdfWarnMode,
      extraQpdfArgs: extraQpdfArgs ?? this.extraQpdfArgs,
      preserveLog: preserveLog ?? this.preserveLog,
      logStdout: logStdout ?? this.logStdout,
      logStderr: logStderr ?? this.logStderr,
    );
  }

  // ---- Helpers para listas de args ----
  List<String> buildQpdfWarnArgs() {
    switch (qpdfWarnMode) {
      case QpdfWarnMode.warningExit0:
        return ['--warning-exit-0'];
      case QpdfWarnMode.noWarn:
        return ['--no-warn'];
      case QpdfWarnMode.normal:
      default:
        return const [];
    }
  }

  List<String> buildOcrmypdfModeArgs() {
    switch (ocrMode) {
      case OCRMode.redoOCR:
        return ['--redo-ocr'];
      case OCRMode.skipText:
      default:
        return ['--skip-text'];
    }
  }

  // Parser simple de argumentos libres (con comiñas)
  List<String> parseFreeArgs(String s) {
    final r = RegExp(r'''("([^"]*)"|'([^']*)'|[^\s]+)''');
    final out = <String>[];
    for (final m in r.allMatches(s)) {
      final g = (m.group(2) ?? m.group(3) ?? m.group(0)!)!;
      out.add(g.replaceAll('"', '').replaceAll("'", ''));
    }
    return out;
  }

  // ---- Serialización ----
  Map<String, Object?> toJson() => {
        'ocrMode': ocrMode.index,
        'ocrmypdfVerbosity': ocrmypdfVerbosity,
        'extraOcrmypdfArgs': extraOcrmypdfArgs,
        'qpdfWarnMode': qpdfWarnMode.index,
        'extraQpdfArgs': extraQpdfArgs,
        'preserveLog': preserveLog,
        'logStdout': logStdout,
        'logStderr': logStderr,
      };

  static AppSettings fromJson(Map<String, Object?> map) {
    OCRMode om(int? i) => (i != null && i >= 0 && i < OCRMode.values.length)
        ? OCRMode.values[i]
        : OCRMode.skipText;
    QpdfWarnMode qm(int? i) =>
        (i != null && i >= 0 && i < QpdfWarnMode.values.length)
            ? QpdfWarnMode.values[i]
            : QpdfWarnMode.normal;

    return AppSettings(
      ocrMode: om(map['ocrMode'] as int?),
      ocrmypdfVerbosity: (map['ocrmypdfVerbosity'] as int?) ?? 1,
      extraOcrmypdfArgs: (map['extraOcrmypdfArgs'] as String?) ?? '',
      qpdfWarnMode: qm(map['qpdfWarnMode'] as int?),
      extraQpdfArgs: (map['extraQpdfArgs'] as String?) ?? '',
      preserveLog: (map['preserveLog'] as bool?) ?? false,
      logStdout: (map['logStdout'] as bool?) ?? true,
      logStderr: (map['logStderr'] as bool?) ?? false,
    );
  }
}
