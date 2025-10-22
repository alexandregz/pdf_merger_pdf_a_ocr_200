import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui; // Rect, Offset, Size
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Inserta páxinas de índice ao comezo dun PDF existente.
/// [inputPath] é o PDF base (xa pasado por OCR/PDF-A ou, se OCR OFF, unha copia).
/// [titles] son os nomes dos ficheiros orixinais na orde unida.
/// [pageCounts] é o número de páxinas de cada ficheiro na mesma orde.
/// Devolve a ruta dun novo PDF con índice e ligazóns.
Future<String> insertTocAtBeginning({
  required String inputPath,
  required List<String> titles,
  required List<int> pageCounts,
}) async {
  final bytes = await File(inputPath).readAsBytes();
  final doc = PdfDocument(inputBytes: bytes);

  if (doc.pages.count == 0 || titles.isEmpty || pageCounts.isEmpty) {
    // nada que facer: devolvemos unha copia
    final outPath = p.setExtension(inputPath, '.with_toc.pdf');
    await File(inputPath).copy(outPath);
    doc.dispose();
    return outPath;
  }

  // Cálculo de offsets (0-based) onde comeza cada documento orixinal
  final starts = <int>[];
  var acc = 0;
  for (final n in pageCounts) {
    starts.add(acc);
    acc += n;
  }

  // Tamaño base (collemos o da primeira páxina para que o TOC manteña o mesmo)
  final firstSize = doc.pages[0].size;
  final pageWidth = firstSize.width;
  final pageHeight = firstSize.height;

  // Axustamos o pageSettings para as páxinas que IMOS inserir
  doc.pageSettings.size = ui.Size(pageWidth, pageHeight);
  // De preferires sen marxes:
  // doc.pageSettings.margins.all = 0;

  // Tipografías e layout
  final fontTitle =
      PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold);
  final fontItem = PdfStandardFont(PdfFontFamily.helvetica, 14);
  const margin = 40.0;
  final lineHeight = fontItem.size * 1.6;

  // Canto cabe por páxina
  final availableHeight = pageHeight - margin * 2 - fontTitle.size - 16;
  final itemsPerPage = max(1, availableHeight ~/ lineHeight);
  final totalItems = titles.length;
  final totalTocPages = (totalItems / itemsPerPage).ceil();

  // Inserimos as páxinas de TOC ao comezo
  final tocPages = <PdfPage>[];
  for (var i = 0; i < totalTocPages; i++) {
    tocPages.add(doc.pages.insert(i));
  }

  // Bookmarks raíz
  final bookmarksRoot = doc.bookmarks;

  // Debuxo + anotacións
  for (var pi = 0; pi < totalTocPages; pi++) {
    final page = tocPages[pi];
    final g = page.graphics;

    // Título
    g.drawString(
      'ÍNDICE',
      fontTitle,
      bounds: ui.Rect.fromLTWH(
        margin,
        margin,
        pageWidth - margin * 2,
        fontTitle.size + 10,
      ),
    );

    var y = margin + fontTitle.size + 16;
    final startItem = pi * itemsPerPage;
    final endItem = min(startItem + itemsPerPage, totalItems);

    for (var idx = startItem; idx < endItem; idx++) {
      final title = titles[idx];

      // Debuxamos o texto do elemento
      final textRect =
          ui.Rect.fromLTWH(margin, y, pageWidth - margin * 2, lineHeight);
      g.drawString(title, fontItem, bounds: textRect);

      // Destino: primeira páxina dese ficheiro dentro do total
      // O TOC está inserido ao comezo, así que hai que “desprazar” polos TOC pages
      final targetPageIndex = tocPages.length + starts[idx]; // 0-based
      final targetPage = doc.pages[targetPageIndex];

      // Ligazón clickable na mesma área do texto (engadimos un pequeno padding vertical)
      final linkRect =
          ui.Rect.fromLTWH(margin, y - 2, pageWidth - margin * 2, lineHeight + 4);

      // IMPORTANTE: Syncfusion usa coordenadas con orixe arriba-esquerda para destinos
      final destination = PdfDestination(targetPage, ui.Offset(0, 0));

      // PdfDocumentLinkAnnotation = ligazón interna (soportada por Syncfusion)
      final link = PdfDocumentLinkAnnotation(linkRect, destination)
        ..border = PdfAnnotationBorder(0); // sen caixa arredor
      page.annotations.add(link);

      // Tamén engadimos bookmark (útil se o visor non mostra as anotacións)
      final bm = bookmarksRoot.add(title);
      bm.destination = destination;

      y += lineHeight;
    }
  }

  // Gardamos nun novo ficheiro
  final outPath = p.setExtension(inputPath, '.with_toc.pdf');
  final outBytes = await doc.save();
  await File(outPath).writeAsBytes(outBytes, flush: true);
  doc.dispose();
  return outPath;
}

/// Conta as páxinas dun PDF. Útil para preparar os offsets do TOC.
Future<int> countPagesOfFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final doc = PdfDocument(inputBytes: bytes);
  final n = doc.pages.count;
  doc.dispose();
  return n;
}
