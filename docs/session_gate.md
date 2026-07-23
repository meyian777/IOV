# OSvoz Session Gate

## Objetivo

La puerta de sesion protege el inicio de OSvoz antes de abrir el command center. La voz inicia el flujo y alinea el idioma; la autenticacion local del sistema confirma la identidad y abre la app sin pedir una tercera frase.

## Flujo actual

1. `Voz inicial`: OSvoz empieza escuchando. El usuario dice `inicia mi sesion` o `start my session`.
2. `Idioma`: OSvoz alinea el idioma inicial segun la frase hablada.
3. `Presencia`: OSvoz intenta validar de forma silenciosa si el usuario origen esta presente, por ejemplo con Apple Watch cercano, sesion local confiable o dispositivo ya autorizado.
4. `Identidad`: si la presencia no basta, macOS valida al usuario con `LocalAuthentication`, usando Face ID, Touch ID o autenticacion local disponible.
5. `Sesion activa`: el command center se abre inmediatamente cuando la identidad local fue aceptada.

## Estados visibles

- `Escuchando`: OSvoz espera la intencion hablada de iniciar sesion.
- `Sesion solicitada`: el usuario pidio entrar por voz y el idioma quedo alineado.
- `Confirmando presencia`: OSvoz intenta comprobar el usuario origen de forma silenciosa.
- `Verificando identidad`: macOS esta mostrando la validacion biometrica/local.
- `Identidad verificada`: la identidad local paso y OSvoz abre el command center.
- `Sesion activa`: la app entra al command center.
- `blocked`: el usuario puede reintentar si falla la biometria.

## Consideraciones de seguridad

- OSvoz no guarda datos biometricos. La verificacion queda delegada a macOS.
- La voz no es un secreto. OSvoz no debe pedir PIN, codigo o password hablado.
- Voice ID es opcional durante el uso y puede reforzar acciones posteriores segun su riesgo; no bloquea el inicio despues de una biometria valida.
- La identidad fuerte debe venir del dispositivo origen: Face ID, Touch ID, Secure Enclave, passkeys o autenticacion local equivalente.
- Apple Watch puede actuar como senal de presencia cercana, pero no debe ser el unico factor para acciones sensibles.
- En lugares publicos, el usuario debe poder iniciar con voz sin revelar credenciales: `inicia mi sesion` solo dispara la autenticacion privada del dispositivo.
- Las acciones sensibles posteriores deben mantener preview y confirmacion antes de aplicar cambios.
- El inicio de sesion no autoriza todas las acciones. OSvoz debe elevar seguridad segun el riesgo:
  - Nivel 1: wake word + sesion activa.
  - Nivel 2: dispositivo confiable + Voice ID + preview.
  - Nivel 3: dispositivo confiable + Face ID/Touch ID + Apple Watch/presencia + passkey + preview explicito.
- Face ID por si solo no basta para acciones criticas si existe riesgo de coaccion.

## Prueba real recomendada

1. Abrir OSvoz desde `./scripts/run_macos.sh`.
2. Confirmar que aparece la puerta de sesion antes del command center.
3. Decir: `inicia mi sesion` o `start my session`.
4. Completar Face ID, Touch ID o autenticacion local.
5. Verificar que el command center se abre directamente, sin pedir confirmacion de voz.
6. Tocar el microfono y preguntar: `ok, en que estamos trabajando`.
7. Confirmar que aparece `Estoy pensando...` y luego una respuesta, no `ambient_speech_ignored`.
8. Decir `IOV, abre Terminal` y confirmar que la orden se interpreta y ejecuta.

## Escenarios automatizados cubiertos

- Inicio por voz: detecta `inicia mi sesion`, `start my session` y `sign me in`.
- Biometria confirmada: abre el command center despues de la intencion hablada sin invocar la confirmacion de voz.
- Gate de dos pasos: muestra solo `Idioma` e `Identidad`; no muestra `Voz`, `Confirmacion` ni `Reintentar voz`.
- Identidad local fallida: mantiene al usuario en el gate, muestra `No pude verificarte` y permite `Reintentar identidad`.
- Idioma detectado: conserva ingles o español desde la frase inicial al entrar.

## Proxima tarea de UX por voz

- Agregar comandos hablados dentro del gate: `atras`, `cambiar idioma`, `español` y `english`.
- Mantener escritura como opcion secundaria, nunca como requisito para iniciar sesion.
- Mostrar siempre el estado actual y la siguiente accion esperada, pero permitir corregir el idioma por voz.
- Eliminar cualquier flujo que dependa de dictar un secreto en voz alta. Si se requiere una prueba adicional, debe ser biometrica, passkey, aprobacion silenciosa del dispositivo o confirmacion dentro de una app segura.
- Integrar presencia confiable con Apple Watch/watchOS cuando sea posible: `OSvoz, estoy aqui` debe iniciar una validacion amigable y silenciosa antes de pedir Face ID.

## Fallos esperados y manejo

- Biometria cancelada: mostrar estado bloqueado y permitir reintento.
- Voz inicial no reconocida: mantener al usuario en la seleccion de idioma y pedir repetir la frase de inicio.
- Idioma ambiguo: usar el idioma del sistema como base y realinear con la primera frase reconocida.
- Backend lento: mostrar estado pendiente inmediatamente para evitar que la interfaz parezca congelada.
- Factor fuerte faltante en accion critica: bloquear la accion, explicar el factor faltante y no ejecutar nada.
- Posible coaccion: no depender solo del rostro para nivel 3; requerir segundo factor privado.

## Siguiente capa empresarial

El gate actual valida la sesion local. Para un uso empresarial conviene agregar una capa de cuenta antes o alrededor de este gate:

1. Registro/inicio con correo empresarial, nombre completo y telefono.
2. Activacion privada del dispositivo con passkey, enlace seguro o codigo fuera de voz; nunca dictado en voz alta.
3. Base de datos de usuarios, organizaciones, roles, dispositivos autorizados y auditoria de sesiones.
4. Politicas por empresa: dominios permitidos, expiracion de sesion, permisos de edicion y aprobaciones.
5. Recuperacion segura: revalidacion privada y autenticacion local si cambia el dispositivo.

Esta capa debe vivir en backend y base de datos; el gate local solo debe consumir el estado `usuario autorizado`, no decidir pertenencia empresarial por si solo.
