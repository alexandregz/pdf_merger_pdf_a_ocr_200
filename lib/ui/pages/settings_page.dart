import 'package:flutter/material.dart';
import '../../models/app_settings.dart';
import '../../services/app_settings_store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _store = AppSettingsStore();
  AppSettings _settings = const AppSettings();
  final _ocrArgsCtrl = TextEditingController();
  final _qpdfArgsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await _store.load();
    setState(() {
      _settings = s;
      _ocrArgsCtrl.text = s.extraOcrmypdfArgs;
      _qpdfArgsCtrl.text = s.extraQpdfArgs;
    });
  }

  Future<void> _save() async {
    await _store.save(_settings.copyWith(
      extraOcrmypdfArgs: _ocrArgsCtrl.text,
      extraQpdfArgs: _qpdfArgsCtrl.text,
    ));
    if (mounted) Navigator.of(context).pop(true); // devolve true se cambiou
  }

  @override
  void dispose() {
    _ocrArgsCtrl.dispose();
    _qpdfArgsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Axustes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
            tooltip: 'Gardar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('OCRmyPDF', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          SegmentedButton<OCRMode>(
            segments: const [
              ButtonSegment(value: OCRMode.skipText, label: Text('--skip-text')),
            ButtonSegment(value: OCRMode.redoOCR, label: Text('--redo-ocr')),
            ],
            selected: {_settings.ocrMode},
            onSelectionChanged: (set) {
              setState(() => _settings = _settings.copyWith(ocrMode: set.first));
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _ocrArgsCtrl,
            decoration: const InputDecoration(
              labelText: 'Parámetros extra para ocrmypdf',
              hintText: '--deskew --threshold 0.6',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              const Text('Verbosidade (-v):'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _settings.ocrmypdfVerbosity,
                items: const [0, 1, 2, 3]
                    .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _settings = _settings.copyWith(ocrmypdfVerbosity: v));
                  }
                },
              ),
            ],
          ),

          const Divider(height: 32),

          const Text('qpdf', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          DropdownButtonFormField<QpdfWarnMode>(
            value: _settings.qpdfWarnMode,
            decoration: const InputDecoration(
              labelText: 'Advertencias',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: QpdfWarnMode.normal,
                child: Text('Normal (sen extra)'),
              ),
              DropdownMenuItem(
                value: QpdfWarnMode.warningExit0,
                child: Text('--warning-exit-0'),
              ),
              DropdownMenuItem(
                value: QpdfWarnMode.noWarn,
                child: Text('--no-warn'),
              ),
            ],
            onChanged: (m) {
              if (m != null) setState(() => _settings = _settings.copyWith(qpdfWarnMode: m));
            },
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _qpdfArgsCtrl,
            decoration: const InputDecoration(
              labelText: 'Parámetros extra para qpdf',
              hintText: '--decrypt --stream-data=compress',
              border: OutlineInputBorder(),
            ),
          ),

          const Divider(height: 32),

          // ← NOVO: checkbox conservar log
          CheckboxListTile(
            value: _settings.preserveLog,
            onChanged: (v) {
              if (v != null) {
                setState(() => _settings = _settings.copyWith(preserveLog: v));
              }
            },
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Conservar log ao rematar'),
            subtitle: const Text('Se está activado, ao pechar o resumo só se limpa a lista de ficheiros.'),
          ),

          // stdout ocrmypdf
          CheckboxListTile(
            value: _settings.logStdout,
            onChanged: (v) {
              if (v != null) {
                setState(() => _settings = _settings.copyWith(logStdout: v));
              }
            },
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Engadir a log stdout'),
          ),

          // stderr ocrmypdf
          CheckboxListTile(
            value: _settings.logStderr,
            onChanged: (v) {
              if (v != null) {
                setState(() => _settings = _settings.copyWith(logStderr: v));
              }
            },
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Engadir a log stderr'),
          ),


          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Gardar'),
          ),
        ],
      ),
    );
  }
}
