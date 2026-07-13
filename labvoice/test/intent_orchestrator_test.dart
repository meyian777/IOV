import 'package:flutter_test/flutter_test.dart';
import 'package:labvoice/services/intent_orchestrator.dart';

void main() {
  test('crea un plan estructurado para trabajo, musica y resumen', () {
    final plan = IntentOrchestrator.plan(
      'abre VS Code, pon una canción de Banda Inventada en YouTube y dime en qué vamos',
    );

    expect(plan.intent, 'compound_task');
    expect(plan.route, 'local_structured_orchestrator');
    expect(plan.tasks.map((task) => task.type), [
      OSvozTaskType.openApp,
      OSvozTaskType.playMedia,
      OSvozTaskType.summarizeProject,
    ]);
    final mediaTask = plan.tasks.firstWhere(
      (task) => task.type == OSvozTaskType.playMedia,
    );
    expect(mediaTask.parameters['query'], contains('banda inventada'));
  });

  test('detecta resumen aunque la frase sea conversacional', () {
    final plan = IntentOrchestrator.plan(
      'sigamos con el proyecto de ayer, abre visual studio code y dame un resumen',
    );

    expect(plan.intent, 'compound_task');
    expect(
      plan.tasks.map((task) => task.type),
      containsAll([OSvozTaskType.openApp, OSvozTaskType.summarizeProject]),
    );
  });

  test('puede mezclar archivos con acciones del entorno', () {
    final plan = IntentOrchestrator.plan(
      'abre terminal y lista los archivos principales',
    );

    expect(plan.intent, 'compound_task');
    expect(
      plan.tasks.map((task) => task.type),
      containsAll([OSvozTaskType.openApp, OSvozTaskType.listFiles]),
    );
  });

  test('infiere YouTube para una peticion simple de musica', () {
    final plan = IntentOrchestrator.plan('pon una canción de Sonido Libre');

    expect(plan.tasks.single.type, OSvozTaskType.playMedia);
    expect(plan.tasks.single.target, 'youtube');
    expect(plan.tasks.single.parameters['query'], contains('sonido libre'));
  });

  test('limpia comandos de entorno fuera de la busqueda musical', () {
    final plan = IntentOrchestrator.plan(
      'abre visual studio code, pon una cancion de Banda Solar y dime en que vamos',
    );
    final mediaTask = plan.tasks.firstWhere(
      (task) => task.type == OSvozTaskType.playMedia,
    );

    expect(mediaTask.parameters['query'], 'banda solar');
  });

  test('extrae artista en frases naturales con youtube', () {
    final plan = IntentOrchestrator.plan(
      'abre visual studio code, reproduce Proyecto Lunar en YouTube y dime en que vamos',
    );
    final mediaTask = plan.tasks.firstWhere(
      (task) => task.type == OSvozTaskType.playMedia,
    );

    expect(mediaTask.parameters['query'], 'proyecto lunar');
  });

  test('entiende artistas arbitrarios en ingles y espanol', () {
    final spanish = IntentOrchestrator.plan(
      'reproduce Artista Delta en YouTube',
    );
    final english = IntentOrchestrator.plan('play North Signal on YouTube');

    expect(spanish.tasks.single.parameters['query'], 'artista delta');
    expect(english.tasks.single.parameters['query'], 'north signal');
  });

  test('respeta plataformas musicales explicitas', () {
    final spotify = IntentOrchestrator.plan(
      'reproduce Grupo Prisma en Spotify',
    );
    final apple = IntentOrchestrator.plan('play Blue Horizon on Apple Music');

    expect(spotify.tasks.single.target, 'spotify');
    expect(spotify.tasks.single.parameters['query'], 'grupo prisma');
    expect(apple.tasks.single.target, 'apple_music');
    expect(apple.tasks.single.parameters['query'], 'blue horizon');
  });

  test('orquesta busqueda musical en spotify sin usar chat', () {
    final plan = IntentOrchestrator.plan('abre North Signal en Spotify');

    expect(plan.tasks.single.type, OSvozTaskType.playMedia);
    expect(plan.tasks.single.target, 'spotify');
    expect(plan.tasks.single.parameters['query'], 'north signal');
  });

  test('no agrega resumen si el usuario no lo pidio explicitamente', () {
    final plan = IntentOrchestrator.plan(
      'abre VS Code y reproduce Sonido Libre en YouTube',
    );

    expect(
      plan.tasks.map((task) => task.type),
      isNot(contains(OSvozTaskType.summarizeProject)),
    );
  });

  test('planea ejecucion de pruebas con resumen ejecutivo', () {
    final plan = IntentOrchestrator.plan(
      'ejecuta las pruebas y explicame el resultado en un resumen',
    );

    expect(plan.intent, 'single_task');
    expect(plan.executiveSummary, isTrue);
    expect(plan.tasks.single.type, OSvozTaskType.runDiagnostics);
    expect(plan.tasks.single.canRunInParallel, isFalse);
  });

  test('rutea variantes naturales de diagnostico sin caer a chat', () {
    final commands = [
      'haz una prueba del proyecto y dame resumen',
      'corre test y explica solo lo basico',
      'analiza las pruebas del proyecto',
      'ejecuta diagnostico y resume el resultado',
      'run the tests and explain the result',
    ];

    for (final command in commands) {
      final plan = IntentOrchestrator.plan(command);

      expect(
        plan.tasks.map((task) => task.type),
        contains(OSvozTaskType.runDiagnostics),
        reason: command,
      );
    }
  });

  test('combina entorno, diagnostico y resumen ejecutivo', () {
    final plan = IntentOrchestrator.plan(
      'abre VS Code, ejecuta las pruebas y explicame el resultado solo lo basico',
    );

    expect(plan.intent, 'compound_task');
    expect(plan.executiveSummary, isTrue);
    expect(plan.tasks.map((task) => task.type), [
      OSvozTaskType.openApp,
      OSvozTaskType.runDiagnostics,
    ]);
  });

  test('divide frase compuesta aunque Whisper transcriba VS Code imperfecto', () {
    final plan = IntentOrchestrator.plan(
      'Abreviso el estudio code, Dame el Estado del sistema y Dame la lista de los archivos principales',
    );

    expect(plan.intent, 'compound_task');
    expect(plan.tasks.map((task) => task.type), [
      OSvozTaskType.openApp,
      OSvozTaskType.operatorStatus,
      OSvozTaskType.listFiles,
    ]);
  });

  test('recupera intenciones desde transcripcion muy imperfecta', () {
    final plan = IntentOrchestrator.plan(
      'Abrevisual estudio como mostrame esta ols sistema listarchos principales respuesta final con todo junto',
    );

    expect(plan.intent, 'compound_task');
    expect(plan.tasks.map((task) => task.type), [
      OSvozTaskType.openApp,
      OSvozTaskType.operatorStatus,
      OSvozTaskType.listFiles,
    ]);
  });
}
