// lib/services/update_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:http/io_client.dart';


// timeout de update, para que non quede colgada a app en windows
const _fetchTimeout = Duration(seconds: 3);

/// Estrutura sinxela cos datos do manifest remoto
class UpdateInfo {
  final Version latest;
  final String url;     // URL a .exe (Win) ou .dmg/.pkg (macOS)
  final String notes;   // texto opcional coas novidades
  const UpdateInfo(this.latest, this.url, this.notes);
}


/// Descarga e interpreta o manifest JSON co formato:
/// { "latest": "1.0.2", "notes": "....", "url": "https://..." }
Future<UpdateInfo?> fetchUpdateInfo(Uri manifestUrl, {Duration timeout = _fetchTimeout}) async {
  final httpClient = HttpClient()..connectionTimeout = timeout;
  final client = IOClient(httpClient);

  try {
    final res = await client.get(manifestUrl).timeout(timeout);
    if (res.statusCode != 200 || res.body.isEmpty) return null;

    final j = jsonDecode(res.body) as Map<String, dynamic>;

    final latestStr = j['latest'] as String?;
    if (latestStr == null) return null;
    final latest = Version.parse(latestStr);

    final notes = (j['notes'] as String?) ?? '';

    // Preferimos "assets" por plataforma; se non existe, caemos a "url".
    final assets = (j['assets'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    String? url;
    if (Platform.isWindows) {
      url = assets['windows'] as String?;
    } else if (Platform.isMacOS) {
      url = assets['macos'] as String?;
    } else {
      url = assets['windows'] as String?; // fallback igual que no teu código
    }
    url ??= j['url'] as String?; // fallback extra por se existe "url" no manifest

    if (url == null || url.isEmpty) return null;

    return UpdateInfo(latest, url, notes);
  } on TimeoutException {
    debugPrint('Timeout conectando con $manifestUrl');
    return null;
  } on SocketException catch (e) {
    debugPrint('Erro de socket: $e');
    return null;
  } on FormatException catch (e) {
    debugPrint('JSON inválido no manifest: $e');
    return null;
  } catch (e, st) {
    debugPrint('Erro inesperado en fetchUpdateInfo: $e\n$st');
    return null;
  } finally {
    client.close();
  }
}

/// Compara a versión instalada coa do manifest (true se hai nova)
Future<bool> isNewerThanInstalled(Version latest) async {
  final info = await PackageInfo.fromPlatform();
  // pubspec: version: 1.2.3+45 -> info.version = "1.2.3"
  Version current;
  try {
    current = Version.parse(info.version);
  } catch (_) {
    final norm = info.version.split('+').first.split('-').first;
    current = Version.parse(norm);
  }
  return latest > current;
}

/// Lanza o actualizador en Windows:
/// - baixa o .exe ao TEMP
/// - execútao con flags silenciosos de Inno Setup
/// - pecha a app para permitir substituír ficheiros
Future<void> runUpdaterWindows(UpdateInfo u) async {
  // try {
  //   final tmp = await Directory.systemTemp.createTemp('up_');
  //   final dest = File('${tmp.path}\\update_setup.exe');

  //   final req = http.Request('GET', Uri.parse(u.url));
  //   final resp = await http.Client().send(req);
  //   final sink = dest.openWrite();
  //   await resp.stream.pipe(sink);
  //   await sink.close();

  //   await Process.start(dest.path, const [
  //     '/VERYSILENT', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'
  //   ]);

  //   exit(0);
  // } catch (e) {
  //   // opcional: log externo
  // }

  // polo de agora, que descargue o .exe
  final uri = Uri.parse(u.url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);

}

/// Ruta simple en macOS: abrir a URL de descarga no navegador.
/// (Para auto-update “real” sen interacción, usar Sparkle nunha fase posterior.)
Future<void> runUpdaterMacOS_OpenUrl(UpdateInfo u) async {
  final uri = Uri.parse(u.url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Comprobación completa + diálogo de confirmación.
Future<void> checkForUpdates(
  BuildContext context, {
  required Uri manifestUrl,
}) async {
  final info = await fetchUpdateInfo(manifestUrl);
  if (info == null) return;

  if (!await isNewerThanInstalled(info.latest)) return;

  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Nova versión dispoñible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versión dispoñible: ${info.latest}'),
          const SizedBox(height: 8),
          if (info.notes.isNotEmpty) ...[
            const Text('Novidades:'),
            const SizedBox(height: 6),
            Text(info.notes),
            const SizedBox(height: 8),
          ],
          const Text('Queres actualizar agora?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('Máis tarde'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('Actualizar'),
        ),
      ],
    ),
  );

  if (ok == true) {
    if (Platform.isWindows) {
      await runUpdaterWindows(info);
    } else if (Platform.isMacOS) {
      await runUpdaterMacOS_OpenUrl(info);
    } else {
      // Outras plataformas: abrir URL
      await runUpdaterMacOS_OpenUrl(info);
    }
  }
}
