import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';


String _fmt(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double b = bytes.toDouble();
  int i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(2)} ${units[i]}';
}

Future<void> showSuccessResultDialog(
  BuildContext context, {
  required String savePath,
  required int sizeBytes,
  required int pageCount,
  required bool pdfaLikely,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Resultado',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, anim1, anim2) {
      final fileName = p.basename(savePath);
      final dirName = p.dirname(savePath);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
          child: Material(
            elevation: 20,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'PDF creado correctamente',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      padding: const EdgeInsets.all(16),
                      child: DefaultTextStyle(
                        style: Theme.of(context).textTheme.bodyMedium!,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ficheiro: $fileName',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            SelectableText(dirName,
                                style: const TextStyle(fontFamily: 'monospace')),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: Text('Peso: ${_fmt(sizeBytes)}')),
                                Expanded(child: Text('Páxinas: $pageCount')),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Text('PDF/A:'),
                                const SizedBox(width: 6),
                                Icon(
                                  pdfaLikely ? Icons.verified : Icons.help_outline,
                                  color: pdfaLikely ? Colors.green : Colors.orange,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    pdfaLikely
                                        ? 'Xerado como PDF/A (ocrmypdf)'
                                        : 'Non se puido verificar automaticamente',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text('Validadores externo PDF/A:'),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => launchUrl(Uri.parse('https://www.pdfforge.org/online/en/validate-pdfa')),
                              child: const Text(
                                'https://www.pdfforge.org/online/en/validate-pdfa',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.blue,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.check),
                          label: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
