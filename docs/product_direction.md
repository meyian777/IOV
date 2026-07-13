# IOV Product Direction

Nota de migracion: `IOV` es el nombre de producto desde esta etapa. `OSvoz`
puede aparecer todavia como nombre historico o interno mientras se completa la
migracion ordenada en codigo, rutas, textos y documentacion.

## Enfoque actual

IOV debe empezar como una experiencia universal de voz para operar el sistema y trabajar con codigo. No debe presentarse inicialmente como una herramienta de hospital, banco u otro sector especifico. Esos sectores vendran despues como integraciones, planes empresariales o adaptadores regulados.

La prioridad inmediata es que el usuario sienta que puede trabajar sin manos:
voz natural, baja latencia, estado claro y seguridad silenciosa.

## Inicio de sesion

El inicio debe ser simple, pero muy seguro:

1. El usuario dice `inicia mi sesion` o `start my session`.
2. IOV detecta idioma e intencion sin pedir teclado.
3. Presencia confiable silenciosa: Apple Watch cercano, dispositivo desbloqueado o sesion local confiable cuando el sistema lo permita.
4. Biometria local: Face ID, Touch ID o huella cuando haga falta subir el nivel de seguridad.
5. Validacion del dispositivo origen con Secure Enclave/passkey o autenticacion local equivalente.
6. Confirmacion de voz como intencion, no como secreto.
7. Entrada al centro operativo de IOV.

Regla critica: IOV no debe pedir PIN, codigo, password ni dato sensible hablado. En un aeropuerto, oficina o lugar publico cualquier persona podria escucharlo. La voz abre el flujo; la identidad real se prueba con biometria, passkeys, dispositivo confiable y permisos por accion.

## Presencia confiable

IOV debe sentirse vivo y seguro desde el primer contacto:

- El usuario puede decir: `IOV, estoy aqui`.
- IOV responde de forma natural: `Te escucho. Confirma tu presencia para continuar.`
- Si Apple Watch, Face ID, Touch ID o passkey confirman al usuario origen, IOV entra sin pedir secretos.
- Si la confianza no alcanza, IOV escala con una frase amable: `Necesito verte para proteger tu sesion.`
- Esta capa debe ser silenciosa siempre que sea posible; la voz inicia el ritual, pero la seguridad ocurre en el dispositivo.
- Apple Watch debe funcionar como senal de proximidad y presencia, no como unico permiso para acciones sensibles.

## Niveles de seguridad por accion

IOV debe clasificar cada comando antes de ejecutarlo. El usuario puede hablar libremente, pero la ejecucion depende del riesgo.

### Nivel 1: comandos normales

Ejemplos: abrir VS Code, abrir Terminal, abrir navegador, reproducir musica, mostrar informacion no sensible.

Requisitos:

- Wake word o escucha activa.
- Sesion IOV activa.
- Sin confirmacion extra si la accion es rutinaria.

### Nivel 2: trabajo personal

Ejemplos: abrir archivos privados, crear drafts, enviar o eliminar email, acceder a datos de clientes, preparar cambios de codigo.

Requisitos:

- Dispositivo confiable.
- Voice ID del usuario origen.
- Preview o resumen antes de aplicar cambios.
- Confirmacion de intencion por voz sin secretos.

### Nivel 3: acciones peligrosas

Ejemplos: enviar dinero, cambiar contrasena, modificar cuentas bancarias, borrar datos sensibles, transferir propiedad, acciones irreversibles.

Requisitos:

- Dispositivo confiable.
- Face ID o Touch ID.
- Apple Watch/presencia cercana cuando este disponible.
- Passkey o Secure Enclave.
- Preview explicito de la accion.
- Confirmacion final privada. La voz no basta.

Regla anti-coaccion: si una persona fuerza al usuario a mostrar el rostro, IOV no debe permitir acciones de nivel 3 solo con Face ID. Debe requerir factores adicionales y, en el futuro, un modo de alerta silenciosa/duress.

## Modelo de acceso

- Acceso gratuito inicial para que el usuario pruebe IOV y entienda el valor.
- Despues de un periodo corto, por ejemplo dos dias, solicitar plan premium para desbloquear control avanzado.
- El control avanzado incluye automatizacion profunda del sistema, navegadores, archivos, apps, integraciones y flujos de voz mas potentes.
- Los niveles empresariales y sectoriales deben ser pagos y configurables por organizacion.
- Los planes avanzados pueden pedir reautenticacion para acciones sensibles, pero nunca deben requerir decir un secreto en voz alta.

## Producto futuro

IOV debe poder evolucionar hacia:

- Control de archivos y proyectos.
- Apertura y operacion de navegadores.
- Integraciones con plataformas autorizadas por el usuario.
- Reproduccion de musica o contenido cuando la plataforma lo permita.
- Redes sociales y apps conectadas mediante APIs oficiales, permisos del usuario y terminos de cada servicio.
- Planes corporativos con roles, auditoria, SSO, OAuth, politicas por empresa y cumplimiento.
- Wearables confiables como Apple Watch para presencia silenciosa.
- Gafas, camaras y dispositivos de realidad aumentada mediante SDKs oficiales.
- Vision asistida para personas ciegas o con baja vision: descripcion de entorno, lectura de texto, reconocimiento de objetos y navegacion asistida con limites claros.
- Programacion accesible: leer codigo, navegar repos, editar multiarchivo y ejecutar pruebas sin depender de mouse, teclado o tactil.

## Puente operativo

La ruta para convertir voz en acciones reales del sistema queda definida en
`docs/iov_operator_capability_bridge.md`. Ese documento separa capacidades por
adaptador, riesgo y nivel de seguridad para que IOV pueda operar como Codex por
voz sin convertir la voz en un secreto inseguro.

## Wearables y accesibilidad

La ruta de accesibilidad queda detallada en
`docs/iov_accessibility_wearables.md`. Ese documento define:

- Integracion de Apple Watch, passkeys y dispositivos confiables como factores silenciosos.
- Ruta Meta Quest/Horizon OS con Passthrough Camera API para vision computacional cuando el hardware y permisos oficiales lo permitan.
- Ruta futura para gafas Meta u otras gafas con camara solo mediante SDK/API oficial y consentimiento explicito.
- Politicas de privacidad: no almacenar imagenes por defecto, procesar localmente cuando sea posible y tratar cada frame de camara como dato sensible.
- Seguridad fisica: IOV debe asistir, no prometer que reemplaza baston, guia, criterio humano o atencion al entorno.

## Principio

Primero: que el usuario diga "wow, puedo trabajar con esto solo con voz".

Despues: planes premium y empresariales para escalar el nivel de control, seguridad, auditoria e integraciones.
