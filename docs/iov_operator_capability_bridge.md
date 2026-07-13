# IOV Operator Capability Bridge

## Objetivo

IOV debe operar como un puente seguro entre la voz del usuario y las
capacidades reales del sistema: leer contexto, abrir apps, controlar navegador,
editar codigo, ejecutar pruebas, conectar APIs externas y resumir resultados.

La voz no debe ser un secreto. La voz inicia, dirige y confirma intencion. La
seguridad real se decide por sesion activa, dispositivo confiable, Voice ID,
biometria local, passkeys, Apple Watch/presencia y auditoria.

## Flujo base

1. El usuario habla: `IOV, abre VS Code, ejecuta las pruebas y explicame el resultado`.
2. Reconocimiento de voz convierte audio en texto.
3. El orquestador divide la frase en tareas.
4. El Capability Bridge clasifica cada tarea por adaptador y riesgo.
5. El Permission Engine exige factores segun nivel.
6. IOV ejecuta solo lo permitido.
7. IOV responde con un resumen breve y util.
8. Todo queda en auditoria sin guardar secretos.

## Niveles

### Nivel 1: rutina

Ejemplos: abrir VS Code, abrir Terminal, abrir navegador, leer estado del
proyecto.

Requisitos:

- Wake word o escucha activa.
- Sesion IOV activa.
- Sin confirmacion extra para acciones reversibles.

### Nivel 2: trabajo personal

Ejemplos: leer archivos privados del proyecto, preparar ediciones, aplicar una
edicion confirmada, ejecutar pruebas, controlar navegador con sesiones abiertas,
conectar APIs externas autorizadas.

Requisitos:

- Dispositivo confiable.
- Voice ID.
- Preview o resumen antes de escribir/ejecutar.
- Confirmacion de intencion por voz.
- Factor silencioso cuando haya datos personales o sesiones externas.

### Nivel 3: critico

Ejemplos: mover dinero, cambiar credenciales, borrar datos sensibles,
operaciones irreversibles.

Requisitos:

- Dispositivo confiable.
- Face ID o Touch ID.
- Apple Watch o presencia cercana si esta disponible.
- Passkey/Secure Enclave.
- Preview explicito.
- Confirmacion final no basada solo en voz.

## Adaptadores

- `native_action_engine`: abre apps y ejecuta acciones locales permitidas.
- `file_access_layer`: lee archivos dentro del proyecto.
- `editor_bridge`: prepara, muestra preview, aplica y deshace cambios.
- `diagnostics_runner`: ejecuta analisis y pruebas.
- `browser_automation`: controla navegador con permisos de accesibilidad.
- `oauth_api_connector`: conecta plataformas externas por OAuth/SSO.
- `critical_action_guard`: bloquea acciones de alto riesgo hasta tener factores fuertes.

## Regla de producto

IOV debe sentirse como Codex operando por voz, pero con limites claros:

- Puede explicar poco y ejecutar mucho cuando el usuario lo pide.
- No debe hablar resumen si el usuario no lo pidio.
- No debe ejecutar cambios de codigo sin preview/confirmacion.
- No debe pedir PIN, password ni codigos hablados.
- No debe usar voz como unico permiso para acciones criticas.

## Estado actual

El backend expone `/core/operator-capabilities` como contrato inicial de esta
fase. Flutter puede usarlo para mostrar estado, decidir mensajes de seguridad y
saber que capacidades estan implementadas, parciales o planeadas.

Flutter ya consulta ese contrato mediante `OperatorCapabilityService` y el
`ActionExecutor` ejecuta un preflight antes de llamar a `/execute`. Ese preflight
resuelve la capacidad requerida, revisa su estado, calcula el nivel de seguridad
y bloquea la accion si faltan factores silenciosos como sesion confiable,
passkey, biometria o Apple Watch segun el riesgo.

Cuando el preflight bloquea una accion protegida, Flutter usa
`SecurityChallengeService` para convertir ese bloqueo en un reto natural de
seguridad local. En macOS/iOS esto llama el canal `osvoz/session_auth`, que usa
Local Authentication del sistema. Si la presencia se confirma, IOV puede
continuar con acciones de rutina o trabajo personal. Si la autenticacion falla,
la accion queda protegida. Para acciones criticas, una biometria local sola no
basta: IOV debe seguir exigiendo factores fuertes adicionales.

Antes de abrir Face ID, Touch ID o el dialogo local, el controlador publica un
estado visible y hablado:

- `security_challenge_pending`: IOV explica por que necesita confirmar presencia.
- `security_challenge_approved`: la presencia fue confirmada y la accion puede continuar.
- `security_challenge_failed`: no se confirmo presencia y la accion no se ejecuto.
- `critical_action_blocked`: una accion critica sigue bloqueada aunque haya biometria local.

Regla UX: la autenticacion local nunca debe aparecer de sorpresa. IOV debe
avisar primero con voz y estado visual, y solo despues abrir el reto del sistema.

## Presencia conversacional

IOV no debe sentirse como una app que solo muestra estados. Debe acompanar al
usuario con pistas auditivas breves mientras una accion se prepara, se valida o
se ejecuta. Esto permite usarlo sin mirar la pantalla.

Reglas:

- Al recibir una accion, IOV confirma con una frase corta: `Recibido. Lo preparo.`
- En acciones largas, IOV emite progreso cada pocos segundos si no esta hablando.
- Las frases deben variar por tipo de tarea para no sonar repetitivas.
- Seguridad debe sonar natural: `Antes de seguir, confirmo que eres tu.`
- La respuesta final debe resumir resultado, no repetir todo el proceso.
- Una pista de progreso nunca debe cortar otra voz en curso.

Implementacion actual:

- `ConversationalPresence` genera frases por idioma, etapa y accion.
- El controlador usa esas frases en preflight, security challenge y ejecucion.
- El temporizador de progreso bajo de 45 segundos a 8 segundos.
- El fallback de voz local de macOS bajo su ritmo para sonar menos robotico.

## Auditoria operativa

Flutter registra eventos locales mediante `AuditLogService` y el backend los
guarda en la cadena tamper-evident de `AuditStore` usando
`POST /core/audit/events`.

Eventos iniciales:

- `operator.preflight`: registra si la capacidad fue aprobada o bloqueada antes de ejecutar.
- `operator.challenge`: registra si la autenticacion local aprobo o bloqueo la accion.
- `operator.execution`: registra solicitud y resultado de ejecucion.

El transporte de auditoria no debe bloquear al operador si el backend cae, pero
el backend debe seguir exponiendo `/core/audit/verify` para validar la cadena.
La metadata se sanitiza antes de enviarse: tokens, claves, contrasenas y secretos
no deben llegar al log.

## Prueba de 4 comandos

1. `IOV, abre terminal`
   - Esperado: accion rutinaria, sin biometria si la sesion es confiable.
   - UI: operador ejecutando accion rutinaria.
   - Audit: `operator.preflight` aprobado y `operator.execution` success.

2. `IOV, abre Visual Studio Code`
   - Esperado: accion rutinaria, abre VS Code.
   - UI: operador ejecutando accion rutinaria.
   - Audit: capacidad `system.open_app`.

3. `IOV, ejecuta las pruebas y explicame el resultado en un resumen`
   - Esperado: si falta confianza, IOV avisa primero y luego pide autenticacion local.
   - UI: `security_challenge_pending`, luego `security_challenge_approved` o `security_challenge_failed`.
   - Audit: `operator.preflight`, `operator.challenge`, `operator.execution`.

4. Simular una accion critica futura desde test interno
   - Esperado: aunque haya biometria local, IOV marca `critical_action_blocked`.
   - UI: accion critica bloqueada.
   - Audit: challenge bloqueado por politica fuerte.
