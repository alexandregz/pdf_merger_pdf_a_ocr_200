import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final y = loadYaml(pubspec) as YamlMap;
  final v = (y['version'] ?? '').toString(); // ex. "1.4.2+37"
  if (v.isEmpty) {
    stderr.writeln('No version in pubspec.yaml');
    exit(1);
  }
  print(v);
}
