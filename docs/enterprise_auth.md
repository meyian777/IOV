# OSvoz Enterprise Authentication

## Objetivo

La autenticacion empresarial de OSvoz debe ser transparente para el usuario y estricta para organizaciones grandes. Cada paso devuelve `stage`, `message`, `required_factors` y `completed_factors` para que Flutter muestre el estado exacto sin adivinar.

## Roles

- `admin`: administra usuarios, acciones sensibles, edicion, lectura y ejecucion.
- `editor`: lee proyecto, prepara/aplica ediciones y ejecuta tareas rutinarias.
- `reader`: lee proyecto y revisa previews, sin aplicar cambios.

## Proveedores y factores

- `passkey`: validacion FIDO/WebAuthn ligada al dispositivo origen.
- `oauth`: proveedor OAuth corporativo.
- `sso`: SSO empresarial.
- `biometric`: Face ID, Touch ID o autenticacion local del dispositivo.
- `voice`: confirmacion de intencion por voz, no secreto.
- `email_code`: factor legado o debug para activacion privada, nunca dictado en voz alta.

## Politica adaptable

- Entorno `standard`: usa passkey/OAuth/SSO; `admin` y acciones sensibles agregan biometria.
- Entornos regulados: requieren passkey/OAuth/SSO, biometria y voz como intencion.
- Acciones sensibles como aplicar ediciones, deshacer, ejecutar comandos o administrar usuarios pueden exigir MFA aunque la sesion ya este iniciada.
- Ningun entorno debe pedir que el usuario diga un PIN, codigo o password en voz alta.

Nota de producto: la UI inicial no debe mostrar sectores como hospital o banco. Esos valores son politicas internas o futuras configuraciones empresariales. El usuario nuevo debe ver un inicio simple y seguro.

## Endpoints

- `GET /auth/enterprise/capabilities`: roles, permisos, proveedores, entornos y mensajes de UI.
- `POST /auth/enterprise/users`: registra usuario con organizacion, correo, nombre completo, telefono y rol.
- `POST /auth/enterprise/session/start`: inicia sesion empresarial y devuelve la siguiente etapa.
- `POST /auth/enterprise/session/verify`: confirma `email_code`, `biometric`, `voice`, `oauth` o `sso`.
- `POST /auth/enterprise/action/authorize`: valida si la sesion y el rol permiten una accion.

## Estados visibles

- `passkey`: aprobar en el dispositivo origen.
- `email_code`: codigo privado fuera de voz, solo si la politica lo exige.
- `oauth`: autorizar con proveedor OAuth.
- `sso`: autorizar con SSO.
- `biometric`: confirmar con Face ID o Touch ID.
- `voice`: confirmar voz para activar OSvoz.
- `ready`: sesion empresarial autorizada.
- `pending_mfa`: falta un factor para una accion sensible.
- `blocked`: usuario, rol, codigo o sesion no validos.

## Escenarios frontend cubiertos

El cliente Flutter tiene una maquina de flujo en `enterprise_auth_flow.dart` para reflejar cada respuesta del backend en estado visible:

- UI integrada futura: debe mostrar dispositivo origen/passkey, biometria, voz, permisos y detalles tecnicos; codigo solo como flujo legacy privado.
- Sesion regulada completa: dispositivo origen/passkey, biometria y voz como intencion.
- Codigo privado incorrecto, si existe por politica legacy: mantiene la sesion visible y muestra el error sin avanzar.
- Reenvio de codigo legacy: permite solicitar un codigo nuevo y continuar con el mas reciente sin dictarlo.
- Backend no disponible: bloquea el inicio con mensaje visible sin congelar la UI.
- Biometria no disponible o cancelada: mantiene el estado en `biometric` y muestra la causa.
- Voz no coincidente: mantiene el estado en `voice` y pide repetir la autorizacion.
- Pruebas visuales reales: la pantalla muestra passkey pendiente, codigo legacy incorrecto, backend caido, biometria fallida y voz no coincidente con estado y etapa visibles.
- Accion sensible: si falta biometria, devuelve `pending_mfa` con `missing_factors`.
- Rol insuficiente: un `reader` queda bloqueado al intentar aplicar ediciones.
- Carga simulada frontend: 24 sesiones paralelas mezclando `reader`, `editor`, `admin`, `bank` y `standard`.

## Escenarios backend cubiertos

- Carga simulada backend: 30 usuarios paralelos con sesiones SQLite independientes y auditoria valida.
- MFA sensible posterior al login: si una accion requiere un factor adicional, el backend actualiza `required_factors` antes de pedir `verify`.
- Aislamiento por rol: los lectores quedan bloqueados y editores/admins completan los factores requeridos.
- Codigo legacy vencido: bloquea la sesion con mensaje claro.
- Bloqueo por intentos fallidos: despues de varios intentos incorrectos, la sesion queda bloqueada temporalmente.
- Reenvio de codigo legacy: limpia intentos fallidos, extiende expiracion y exige el codigo nuevo fuera de voz.

## Auditoria

El backend registra eventos tamper-evident:

- `enterprise.user_registered`
- `enterprise.session_started`
- `enterprise.factor_verified`
- `enterprise.action_authorized`

Los eventos incluyen organizacion, usuario, rol, proveedor, entorno, IP, dispositivo, etapa y resultado. No se guardan codigos, tokens ni secretos en auditoria.

## Escalabilidad

El modulo `enterprise_auth.py` esta aislado del resto del backend para poder moverlo despues a un microservicio o conectarlo con directorios corporativos, sistemas hospitalarios, bancos, IdP SSO y politicas por organizacion.
