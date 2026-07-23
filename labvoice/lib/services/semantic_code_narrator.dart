class SemanticNarrationNode {
  const SemanticNarrationNode({required this.kind, required this.message});

  final String kind;
  final String message;
}

class SemanticCodeTree {
  const SemanticCodeTree({
    required this.path,
    required this.language,
    required this.nodes,
  });

  final String path;
  final String language;
  final List<SemanticNarrationNode> nodes;
}

class SemanticCodeAnalyzer {
  static SemanticCodeTree analyze({
    required String path,
    required String language,
    required String source,
  }) {
    final fileName = path.split('/').last;
    final symbols = _symbols(source);
    final functions = _functions(source);
    final dependencies = _dependencies(source);
    final criticalFlow = functions
        .where(
          (name) => RegExp(
            r'^(main|init|initialize|build|run|start|process|execute|handle|listen)',
            caseSensitive: false,
          ).hasMatch(name),
        )
        .take(5)
        .toList();
    final risks = <String>[];
    if (RegExp(r'\b(TODO|FIXME|HACK)\b').hasMatch(source)) {
      risks.add('hay trabajo pendiente marcado dentro del archivo');
    }
    if (RegExp(
      r'catch\s*\([^)]*\)\s*\{\s*\}',
      multiLine: true,
    ).hasMatch(source)) {
      risks.add('hay errores capturados sin una reacción visible');
    }
    if (source.length > 30_000) {
      risks.add('el archivo concentra demasiada responsabilidad');
    }

    final nodes = <SemanticNarrationNode>[
      SemanticNarrationNode(
        kind: 'purpose',
        message: symbols.isEmpty
            ? 'El archivo $fileName contiene lógica de $language. Primero conviene ubicar su entrada y la responsabilidad que concentra.'
            : 'El propósito de $fileName gira alrededor de ${_spokenList(symbols.take(4))}.',
      ),
      if (criticalFlow.isNotEmpty)
        SemanticNarrationNode(
          kind: 'flow',
          message:
              'El flujo principal pasa por ${_spokenList(criticalFlow)}. Ese es el recorrido que importa antes de mirar detalles internos.',
        ),
      if (functions.isNotEmpty)
        SemanticNarrationNode(
          kind: 'functions',
          message:
              'Las funciones más relevantes que encontré son ${_spokenList(functions.take(7))}. Podemos profundizar en cualquiera si hace falta.',
        ),
      if (dependencies.isNotEmpty)
        SemanticNarrationNode(
          kind: 'dependencies',
          message:
              'Las dependencias que influyen directamente aquí son ${_spokenList(dependencies.take(6))}. Omito las demás porque no cambian la explicación principal.',
        ),
      SemanticNarrationNode(
        kind: 'risks',
        message: risks.isEmpty
            ? 'No veo una alerta estructural obvia en esta primera lectura. El siguiente paso útil es comprobar el flujo con sus pruebas.'
            : 'Los riesgos principales son ${_spokenList(risks)}.',
      ),
    ];
    return SemanticCodeTree(path: path, language: language, nodes: nodes);
  }

  static List<String> _symbols(String source) => RegExp(
    r'\b(?:class|enum|mixin|extension|struct|interface)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).allMatches(source).map((match) => match.group(1)!).toSet().toList();

  static List<String> _functions(String source) {
    final patterns = [
      RegExp(
        r'\b(?:Future(?:<[^>]+>)?|void|bool|int|double|String|dynamic|Widget|Map<[^>]+>|List<[^>]+>)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ),
      RegExp(r'\bdef\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('),
      RegExp(
        r'\b(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>',
      ),
    ];
    return patterns
        .expand((pattern) => pattern.allMatches(source))
        .map((match) => match.group(1)!)
        .where((name) => !name.startsWith('_') || name.length > 2)
        .toSet()
        .toList();
  }

  static List<String> _dependencies(String source) =>
      RegExp(r'''(?:import|from|require)\s*\(?["']([^"']+)["']''')
          .allMatches(source)
          .map((match) {
            final value = match.group(1)!;
            return value
                .split('/')
                .last
                .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
          })
          .toSet()
          .toList();

  static String _spokenList(Iterable<String> values) {
    final items = values.where((value) => value.trim().isNotEmpty).toList();
    if (items.isEmpty) return 'ninguno';
    if (items.length == 1) return items.single;
    return '${items.take(items.length - 1).join(', ')} y ${items.last}';
  }
}

class SemanticCodeNarrator {
  SemanticCodeTree? _tree;
  int _cursor = 0;
  final List<String> _coveredKinds = [];

  bool get active => _tree != null && _cursor < _tree!.nodes.length;
  String? get activePath => _tree?.path;
  int get cursor => _cursor;

  String start(SemanticCodeTree tree) {
    _tree = tree;
    _cursor = 0;
    _coveredKinds.clear();
    return next();
  }

  String next() {
    final tree = _tree;
    if (tree == null) return 'No hay una explicación semántica activa.';
    if (_cursor >= tree.nodes.length) {
      return 'Ya cubrimos los puntos críticos de este archivo.';
    }
    final node = tree.nodes[_cursor++];
    _coveredKinds.add(node.kind);
    return node.message;
  }

  String summary() {
    final tree = _tree;
    if (tree == null || _coveredKinds.isEmpty) {
      return 'Todavía no hay una explicación semántica para resumir.';
    }
    return 'En ${tree.path.split('/').last} ya revisamos ${_coveredKinds.join(', ')}. '
        '${active ? 'Queda contenido crítico por explicar.' : 'La revisión crítica quedó completa.'}';
  }
}
