# OSvoz Authentication QA Checklist

No avanzar a control del sistema, archivos, navegador, musica o integraciones hasta completar esta lista.

## Principio de seguridad

- La voz es interfaz e intencion, no credencial secreta.
- OSvoz nunca debe pedir PIN, codigo, password ni dato sensible hablado.
- La identidad fuerte debe venir del dispositivo origen: Face ID, Touch ID, Secure Enclave, passkeys o autenticacion local equivalente.
- En ambientes publicos, el usuario debe poder entrar sin revelar secretos a personas cercanas.

## Preparacion

- Backend de OSvoz encendido.
- App macOS abierta desde `./scripts/run_macos.sh`.
- CocoaPods limpio con `./scripts/check_no_cocoapods.sh`.
- `flutter analyze` sin issues.
- `flutter test` pasando.
- Tests backend de autenticacion pasando.

## Flujo feliz voz primero

1. Abrir OSvoz.
2. Confirmar que OSvoz aparece escuchando, sin formulario obligatorio.
3. Decir: `inicia mi sesion` o `start my session`.
4. Confirmar que OSvoz detecta la intencion y alinea el idioma.
5. Completar Face ID, Touch ID o autenticacion local.
6. Decir la frase de intencion:
   - Español: `OSvoz, autorizo esta sesion`.
   - English: `OSvoz, I authorize this session`.
7. Confirmar entrada al centro de comando.
8. Cerrar y reabrir OSvoz.
9. Esperado: durante una sesion confiable vigente, OSvoz entra directo sin repetir Face ID/voz.

## Activacion de cuenta futura

- La cuenta puede usar correo, telefono o plan premium, pero esos datos no deben convertirse en secretos hablados.
- Si se requiere activacion, usar enlace seguro, passkey, aprobacion del dispositivo o codigo privado fuera de voz.
- En QA local, cualquier codigo visible debe ser solo debug y nunca parte de la experiencia final.

## Fallos esperados

### Voz inicial no entendida

- Decir una frase sin intencion de iniciar sesion.
- Esperado: mensaje claro pidiendo `inicia mi sesion` o `start my session`.
- Esperado: usuario puede reintentar sin teclado.

### Biometria fallida

- Cancelar Face ID, Touch ID o autenticacion local.
- Esperado: mensaje claro de identidad no confirmada.
- Esperado: usuario puede reintentar.

### Voz no coincidente

- Decir una frase no valida o cancelar voz.
- Esperado: mensaje claro de voz no coincidente/no confirmada.
- Esperado: usuario puede reintentar.

### Idioma equivocado

- Iniciar en español diciendo `inicia mi sesion`.
- Esperado: OSvoz escucha con perfil español.
- Iniciar en ingles diciendo `start my session`.
- Esperado: OSvoz escucha con perfil ingles.
- Esperado: si se equivoca, puede cambiar idioma o reintentar sin reiniciar.

### Sesion local confiable

- Completar voz inicial, identidad local y voz de autorizacion.
- Cerrar y reabrir OSvoz.
- Esperado: la app entra directo si la confianza local sigue vigente.
- Esperado: la confianza local vence automaticamente despues de 24 horas.
- Esperado: acciones sensibles futuras podran pedir Face ID otra vez aunque la sesion general siga activa.

### Accion sensible futura

- Pedir una accion de alto riesgo.
- Esperado: OSvoz muestra preview o resumen hablado.
- Esperado: OSvoz pide reautenticacion privada si el riesgo lo requiere.
- Esperado: OSvoz no pide decir un PIN, codigo o password en voz alta.

### Niveles de riesgo

- Nivel 1: decir `abre VS Code`.
  - Esperado: wake word/sesion activa bastan.
- Nivel 2: pedir abrir archivo privado, crear draft o acceder a datos de clientes.
  - Esperado: requiere dispositivo confiable, Voice ID y preview.
- Nivel 3: pedir `envia dinero`, `cambia la contrasena` o accion irreversible.
  - Esperado: requiere dispositivo confiable, Face ID/Touch ID, Apple Watch/presencia, passkey y preview explicito.
  - Esperado: Face ID solo no autoriza la accion.
  - Esperado: si falta un factor fuerte, OSvoz bloquea sin ejecutar.

## Criterios para avanzar

- El primer inicio se siente voz primero.
- El usuario puede completar el flujo feliz sin teclado ni mouse.
- Ningun secreto se dicta en voz alta.
- Face ID/Touch ID/passkey protegen la identidad real.
- Ningun error deja la app congelada.
- Siempre hay una accion siguiente visible o hablada.
- Los tests automaticos pasan.
- Los fallos principales fueron probados manualmente al menos una vez.
