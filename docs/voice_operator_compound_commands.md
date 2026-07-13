# OSvoz voice operator compound commands

## Estado implementado

- Whisper local transcribe el comando y Flutter alinea el idioma antes de responder.
- Las ordenes locales basicas no dependen del chat remoto: abrir VS Code, abrir Terminal, listar archivos, leer el main de Flutter y consultar el proyecto activo.
- OSvoz tiene un Intent Orchestrator local que convierte frases naturales en tareas estructuradas. Ejemplo:

```json
{
  "intent": "compound_task",
  "route": "local_structured_orchestrator",
  "tasks": [
    {"type": "openApp", "target": "vscode"},
    {"type": "playMedia", "target": "youtube", "parameters": {"query": "artista o cancion solicitada"}},
    {"type": "summarizeProject", "target": "local_session"}
  ]
}
```

- OSvoz puede interpretar variaciones de una orden compuesta como: abrir VS Code, reproducir musica en YouTube y dar un resumen local del proyecto.
- YouTube usa el backend en `/browser/youtube/play`. En macOS intenta abrir Google Chrome, cargar la busqueda y pulsar el primer resultado. Si Chrome no esta disponible o la automatizacion falla, abre la busqueda y lo reporta.
- La voz de salida en macOS usa el motor local `say` como ruta principal para no quedar muda cuando el servicio natural no esta disponible. Voz espanola actual: `Reed (Spanish (Mexico))` a velocidad moderada.

## Frases de prueba

1. `Abre VS Code y reproduce en YouTube una cancion de Artista Libre y dame un resumen.`
2. `Abre VS Code, pon una cancion de Banda Solar en YouTube.`
3. `Pon una cancion de Proyecto Lunar.`
4. `Open VS Code and play a song by North Signal on YouTube.`
5. `Abre Grupo Prisma en Spotify.`
6. `Busca Sonido Libre en Spotify.`
7. `Que proyecto esta activo.`
8. `Lista los archivos principales.`
9. `Lee el archivo principal de Flutter.`
6. `Que proyecto esta activo.`
7. `Lista los archivos principales.`
8. `Lee el archivo principal de Flutter.`

## Resultado esperado

- OSvoz no debe pedir confirmacion para abrir VS Code, Terminal o navegador.
- OSvoz debe hablar la respuesta final.
- La frase compuesta debe ejecutar VS Code y YouTube en paralelo.
- El resumen debe salir de la memoria local de sesion, no del servicio conversacional remoto.
- Si no puede reproducir automaticamente el primer resultado, debe decirlo con claridad y dejar YouTube abierto.
- La busqueda musical no debe incluir comandos de control como `abre VS Code`, `dame un resumen` o `dime en que vamos`.
- OSvoz no debe tener artistas hardcodeados ni corregir nombres de artistas por reglas fijas. La busqueda musical sale del texto capturado por voz.
- Las respuestas de voz se cancelan por generacion: una voz vieja no debe seguir hablando encima de la nueva.
- Para musica, OSvoz debe extraer solo el artista o busqueda musical. Ejemplo: `abre VS Code, reproduce Banda Solar en YouTube y dime en que vamos` debe buscar `Banda Solar`, no la frase completa.
- En Chrome, OSvoz intenta pulsar el primer enlace real de video cuando la pagina termina de cargar. Si YouTube cambia el DOM o bloquea automatizacion, el siguiente paso es un Browser Bridge persistente con extension.
- La intencion musical vive en `MusicIntentParser`: detecta verbos musicales (`reproduce`, `pon`, `toca`, `play`, `quiero escuchar`) y tambien comandos con plataforma explicita (`abre X en Spotify`, `busca X en Apple Music`). Comandos de entorno como `abre VS Code` no se convierten en musica.
- Plataformas reconocidas: YouTube, Spotify y Apple Music. YouTube intenta reproduccion directa; Spotify y Apple Music abren busqueda por ahora hasta integrar APIs autenticadas.
- Si el comando parece musica pero no produce una tarea segura, Flutter responde con una aclaracion local y no llama al chat remoto. Esto evita el mensaje `IA conversacional no disponible` en frases truncadas, voces de terceros o capturas ambiguas.

## Limites actuales

- La reproduccion real en YouTube depende de automatizacion del navegador. El puente inicial usa Chrome porque permite AppleScript con JavaScript en la pestana activa.
- `Omite el anuncio` intenta pulsar el boton oficial de YouTube cuando aparezca en Chrome.
- `Pon X en YouTube y omite los anuncios` activa un monitor temporal en la pestana de YouTube para pulsar el boton oficial de omitir apenas aparezca. No se implementa bloqueo de anuncios ni evasion no autorizada; si el boton oficial no esta visible o Chrome no permite control, OSvoz debe decirlo.
- Para que el control de Chrome funcione en macOS, Chrome debe tener activado `View > Developer > Allow JavaScript from Apple Events`. Si no esta activado, OSvoz no puede ver ni pulsar el boton oficial desde la pestana.
- Para controlar cualquier dispositivo se necesita un bridge por plataforma: macOS con AppleScript/Accessibility, navegador con extension o DevTools, iOS/Android con intents y accesibilidad autorizada.

## Siguiente mejora tecnica

- Crear un Browser Bridge persistente con estado visible: pagina abierta, video detectado, reproduccion iniciada, boton oficial de omitir disponible.
- Agregar un turn manager para no responder mientras el usuario aun habla.
- Agregar streaming/VAD para capturar frases largas sin cortar al usuario.
- Conectar un modelo con salida JSON estructurada solo para frases ambiguas. El contrato debe producir el mismo esquema del Intent Orchestrator local para que el Task Runner no cambie.
