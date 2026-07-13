# IOV Accessibility and Wearables Roadmap

## Vision

IOV debe ser una capa de operacion por voz para personas que quieren trabajar sin manos y, especialmente, para personas ciegas o con baja vision que tambien pueden programar, navegar sistemas y aportar en ingenieria.

La meta no es reemplazar la seguridad del dispositivo. La meta es combinar voz natural, presencia confiable y vision asistida para que el usuario pueda actuar con autonomia sin decir secretos en voz alta.

## Nombre

- Nombre de producto: `IOV`.
- OSvoz queda como nombre interno historico durante la migracion.
- Los textos nuevos de producto deben usar `IOV`.

## Seguridad base

La voz nunca debe ser el secreto.

- Comandos normales: wake word + sesion activa.
- Trabajo personal: dispositivo confiable + Voice ID + preview.
- Acciones peligrosas: dispositivo confiable + Face ID/Touch ID + Apple Watch/presencia + passkey + preview explicito.
- En lugares publicos no se deben pedir PIN, codigos o passwords hablados.
- Para riesgo de coaccion, Face ID por si solo no basta.

## Flujo seguro sin manos

1. Usuario dice: `IOV, estoy aqui` o `IOV, inicia mi sesion`.
2. IOV detecta idioma e intencion.
3. IOV valida presencia silenciosa: Apple Watch, dispositivo confiable, sesion local o passkey.
4. Si el riesgo sube, pide Face ID/Touch ID o passkey.
5. IOV responde natural: `Te escucho. Que vamos a hacer hoy?`
6. Para acciones criticas, IOV exige segundo factor silencioso y preview explicito.

## Integracion Apple Watch / wearables confiables

Objetivo:

- Usar Apple Watch como senal de presencia cercana.
- Usar gesto fisico o aprobacion del dispositivo como factor silencioso.
- Nunca usar el reloj como unico factor para acciones nivel 3.

Estados sugeridos:

- `watch_nearby`: reloj cercano y emparejado.
- `watch_unlocked`: reloj desbloqueado en la muneca.
- `watch_confirmed`: usuario aprobo un gesto o prompt.
- `watch_unavailable`: escalar a Face ID/Touch ID/passkey.

## Integracion Meta / gafas / camaras

### Ruta Meta Quest / Horizon OS

La ruta documentada por Meta para computer vision es Horizon OS con Passthrough Camera API.

Requisitos oficiales relevantes:

- Horizon OS v74 o superior.
- Quest 3 o Quest 3S.
- Permiso `android.permission.CAMERA` o `horizonos.permission.HEADSET_CAMERA`.
- Passthrough habilitado.

Capacidades relevantes:

- Acceso a camaras RGB frontales.
- Integracion con pipelines ML/CV.
- Casos de uso como identificar objetos especificos, asistentes/guias y feedback sobre tareas.

Restricciones relevantes:

- Los frames de camara son datos del usuario y deben tratarse con politica estricta de privacidad.
- No depender de una resolucion fija; manejar resoluciones y aspect ratios dinamicamente.
- Cuidar rendimiento: la vision debe mantener la experiencia comoda y con alta tasa de frames.

### Ruta gafas Meta / smart glasses

Para Ray-Ban Meta, Ray-Ban Display u otras gafas con camara:

- Tratar la integracion como conector futuro sujeto a SDK/API disponible y permisos oficiales.
- No asumir acceso libre a camara, microfono o stream.
- Priorizar flujos autorizados por el usuario y APIs oficiales.
- Si hay Developer Preview o Device Access Toolkit disponible, construir un adaptador aislado para:
  - comandos de voz desde gafas;
  - presencia del dispositivo;
  - captura autorizada de imagen/video;
  - respuestas auditivas o visuales.

## Arquitectura propuesta

```text
Wearable / glasses / phone
  -> voice capture / presence / camera permission
  -> IOV Device Bridge
  -> backend intent orchestrator
  -> security policy engine
  -> action executor / code editor / browser bridge
```

Componentes:

- `Device Bridge`: adapta Apple Watch, passkeys, Meta/Quest, gafas y sensores.
- `Vision Adapter`: normaliza frames, OCR, objetos, señales y obstaculos.
- `Voice Adapter`: recibe comandos desde microfonos externos o gafas.
- `Security Policy Engine`: decide nivel 1, 2 o 3 antes de ejecutar.
- `Assistive Narrator`: responde con voz breve, clara y accionable.

## Computer vision asistida

Prioridades:

1. Descripcion de entorno: `IOV, que tengo delante?`
2. OCR: leer pantallas, documentos, botones, senales y etiquetas.
3. Reconocimiento de objetos: puertas, escaleras, sillas, personas, cruces.
4. Deteccion de obstaculos: advertencias cortas, no invasivas.
5. Navegacion asistida: instrucciones seguras, con limites claros.
6. Programacion accesible: leer codigo, explicar estructura, navegar archivos, dictar ediciones.

## Seguridad y responsabilidad

IOV no debe prometer seguridad fisica absoluta.

- Para calle, trafico y obstaculos, IOV debe decir que es asistencia, no sustituto de baston, perro guia o criterio del usuario.
- No almacenar imagenes por defecto.
- Procesar en dispositivo cuando sea posible.
- Pedir consentimiento claro para camara/microfono.
- No identificar personas por rostro sin consentimiento y base legal.
- Evitar dar instrucciones peligrosas si la vision no tiene confianza suficiente.

## Roadmap por etapas

### Etapa 1: voz y seguridad local

- Reducir latencia.
- Mejorar voz natural.
- Inicio por voz + biometria silenciosa.
- Voice ID + passkey/Face ID para nivel 2 y 3.

### Etapa 2: Device Bridge

- Abstraccion para Apple Watch/passkey/trusted device.
- Estados de presencia confiable.
- Tests de acciones nivel 1/2/3.

Estado actual de implementacion:

- Flutter tiene `DeviceTrustService` para calcular confianza silenciosa.
- macOS/iOS exponen `canAuthenticate` para saber si Face ID, Touch ID o autenticacion local estan disponibles sin abrir el prompt.
- Las pruebas locales pueden simular factores futuros con:
  - `--dart-define=IOV_SIMULATE_PASSKEY=true`
  - `--dart-define=IOV_SIMULATE_WATCH_NEARBY=true`
  - `--dart-define=IOV_SIMULATE_WATCH_UNLOCKED=true`
  - `--dart-define=IOV_SIMULATE_WATCH_CONFIRMED=true`
- Estas simulaciones son solo para integracion; no sustituyen passkey, Apple Watch ni biometria real en produccion.

### Etapa 3: gafas y captura externa

- Adaptador para comandos de voz desde gafas o microfonos externos.
- Conector Meta/Quest segun SDK oficial disponible.
- Politica de permisos de camara y privacidad.

### Etapa 4: vision asistida

- OCR local.
- Descripcion de escena.
- Deteccion de objetos/obstaculos.
- Narracion segura y breve.

### Etapa 5: programacion accesible avanzada

- Navegar repo por voz.
- Leer archivos largos con resumen incremental.
- Editar multiarchivo con preview.
- Deshacer por voz.
- Ejecutar pruebas y explicar fallos sin usar pantalla.
