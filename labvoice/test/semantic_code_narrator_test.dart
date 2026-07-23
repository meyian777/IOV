import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/semantic_code_narrator.dart';

void main() {
  test('construye un árbol crítico sin leer caracteres línea por línea', () {
    final tree = SemanticCodeAnalyzer.analyze(
      path: 'lib/example.dart',
      language: 'dart',
      source: '''
import 'package:flutter/widgets.dart';
class ExampleController {
  Future<void> initialize() async {}
  void processCommand(String command) {}
}
''',
    );

    expect(tree.nodes.map((node) => node.kind), contains('purpose'));
    expect(tree.nodes.map((node) => node.kind), contains('flow'));
    expect(tree.nodes.map((node) => node.kind), contains('functions'));
    expect(
      tree.nodes.expand((node) => node.message.split(' ')),
      isNot(contains('{')),
    );
  });

  test('continúa desde el siguiente nodo y no reinicia', () {
    final narrator = SemanticCodeNarrator();
    final tree = SemanticCodeAnalyzer.analyze(
      path: 'main.py',
      language: 'python',
      source: 'def main():\n    run()\ndef run():\n    pass\n',
    );

    final first = narrator.start(tree);
    final cursorAfterFirst = narrator.cursor;
    final second = narrator.next();

    expect(first, isNot(second));
    expect(cursorAfterFirst, 1);
    expect(narrator.cursor, 2);
    expect(narrator.summary(), contains('Queda contenido crítico'));
  });
}
