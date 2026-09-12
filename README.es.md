# Ultimate Mortal Kombat 3 — Remake en Godot

**Un remake jugable de la versión iOS de 2011 de *Ultimate Mortal Kombat 3*, reconstruido en Godot 4 — donde cada número del combate sale del binario original y no del criterio de nadie.**

[Primeros pasos](docs/GETTING-STARTED.md) · [Metodología](docs/METHODOLOGY.md) · [Arquitectura](docs/ARCHITECTURE.md) · [Sistema de combate](docs/FIGHT-SYSTEM.md) · [Animación](docs/ANIMATION.md) · [Progreso](docs/PROGRESS.md) · [Divulgación IA](AI-DISCLOSURE.md) · [English](README.md)

**Esta es la segunda mitad de un proyecto de dos repositorios.** El primero es
[**Ultimate-Mortal-Kombat-3-iOS-Recomp**](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp),
que desarma el binario de iOS. Este vuelve a montar un juego con lo que aquel
encuentra. [Cómo encajan](#los-dos-repositorios).

---

## Aquí no se distribuye ningún asset con copyright

**Este repositorio no incluye ningún archivo del juego.** Ni texturas, ni
modelos, ni audio, ni datos de frames — nada que puedas sacar de aquí y usar.
Funciona contra **una copia del juego que aportes tú**.

Lo que vive aquí es código: GDScript que lee los formatos de archivo del propio
juego, y un motor de combate cuyas constantes se recuperaron leyendo el binario
ARM de la versión comercial. Un número recuperado de un binario —una tabla de
hitboxes, una lista de índices de frames— es un hecho sobre cómo se comporta el
software, y se anota aquí igual que se anota la especificación de un formato.
Los archivos del juego se quedan en tu disco, donde `.gitignore` los mantiene
fuera del repositorio.

Necesitas una copia legalmente obtenida de *Ultimate Mortal Kombat 3* para iOS
(versión 1.2.59) para que nada de esto sirva de algo.

---

## Los dos repositorios

Son proyectos separados con objetivos separados, y cada uno sirve sin el otro.
Comparten una cosa: el binario, y lo que se ha aprendido de él.

| | [**Recomp**](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp) — paso uno | **Remake en Godot** — paso dos (este) |
|---|---|---|
| **Pregunta que responde** | *¿Qué hace el original?* | *¿Podemos volver a jugarlo?* |
| **Resultado** | C legible, función a función, contrastada con un recompilador estático ARM→C | Un juego que corre |
| **Regla de fidelidad** | La C debe coincidir con el desensamblado | El *comportamiento* debe coincidir con las medidas |
| **Renderizador** | Las llamadas GL del original, transcritas | El de Godot, escrito de cero |
| **Alcance** | Todo el binario — 4.342 funciones con nombre | El combate primero, y de momento solo Scorpion |
| **Termina cuando** | La C compila y se juega | Se juega como el juego del móvil |

**Por qué dos y no uno.** La decompilación transcribe el original *incluyendo*
cómo habla con el hardware: llama a OpenGL directamente en 366 sitios, porque
el juego de 2011 lo hacía. Poner Godot debajo de eso obligaría a escribir una
capa de pipeline fija sobre el renderizador de Godot, o a editar la
transcripción hasta que dejara de coincidir con el desensamblado. Lo segundo
destruye la única propiedad que hace que una transcripción valga algo.

Así que la separación va por la única costura donde no se pierde nada:

> **La decompilación posee las RESPUESTAS. El remake posee el MOTOR.**

Recomp lee `strike_check_regs` y deduce que la caja de un golpe es
`[X + x - w, X + x]` y no `[X + x, X + x + w]`. Ese hecho no es C ni es GL — es
simplemente verdad. Este repositorio coge hechos así y construye algo jugable
con ellos, sobre un renderizador que funciona en hardware actual, en una
ventana que se redimensiona y con un mando que funciona.

Cuando un número aquí lleva una dirección hexadecimal al lado en un comentario,
esa dirección es una cita al binario que Recomp documenta. Los dos repositorios
son una referencia y una implementación del mismo tema.

---

## Qué funciona ahora mismo

Scorpion, un escenario cada vez, dos jugadores en la misma máquina.

- **Movimiento** — andar, la carrera y su barra de turbo de 48 unidades, salto, salto en diagonal, agacharse, girarse
- **Ataques** — 16 golpes con sus propias hitboxes, daño, daño de roce, reacciones, sonidos, animaciones y *velocidad de animación propia*, incluidos los seis ataques que producen dos botones: la patada alta se vuelve rodilla dentro de 74 unidades, y roundhouse con la palanca atrás
- **Bloqueo** — de pie y agachado, sondeado como lo sondea el motor, y la regla de que un ataque bajo atraviesa el bloqueo de pie
- **Especiales** — el arpón con su cuerda y su arrastre, el teleport punch con su salto de pantalla, y la llave en el aire
- **Reacciones** — golpes, derribos, el lanzamiento del uppercut y su aterrizaje, levantarse, el desplome que cierra el round
- **Presentación** — los sprites del HUD del propio juego y sus monedas de round, sangre, sacudida de pantalla, 44 sonidos y la música de cada escenario
- **Alrededor del juego** — menú de pausa, configuración de botones por jugador con ratón y mando, opciones de vídeo (monitor, resolución, modo de ventana, antialiasing, sincronización vertical, límite de fps), todo guardado entre ejecuciones

[La lista completa, con qué está medido y qué sigue elegido](docs/PROGRESS.md).

## Qué no

Un personaje de veintiséis. Sin IA, sin flujo de combate, sin fatalities, sin
front end más allá de un selector de escenarios, sin online. Siete de los
dieciocho escenarios no están conectados todavía.

---

## Cómo ejecutarlo

```
UMK3.exe -- "D:/juegos/UMK3.app/res"
```

La ruta apunta a la carpeta `res` de tu propia copia extraída. Se recuerda tras
la primera ejecución. [Versión larga](docs/GETTING-STARTED.md).

---

## Cómo funciona la fidelidad

Cada constante del combate es una de tres cosas, y el código dice cuál:

1. **Medida** — leída del binario, con la dirección en el comentario.
   `const UPCUT_VY := -int(18.0 * ONE)   ## measured, 0xffee0000`
2. **Elegida** — todavía no hay medición, y el comentario lo dice claramente en
   vez de dejarte adivinar cuál es cuál.
3. **Generada** — una tabla emitida desde los datos del propio binario, como
   los 27 registros de golpes o los 82 streams de animación. Esos archivos
   ponen GENERATED arriba y no se editan a mano.

La regla que produjo casi todo el trabajo de aquí: **lee la función entera,
sigue la cadena hasta la hoja, y mide — nunca deduzcas por plausibilidad.**
Varias de las cosas que parecían obviamente correctas estaban mal, y la
[página de metodología](docs/METHODOLOGY.md) es en parte una lista de ellas,
porque los errores enseñan más que los aciertos.

---

## Trabajo previo y agradecimientos

- **[Ultimate-Mortal-Kombat-3-iOS-Recomp](https://github.com/MaryNCRT/Ultimate-Mortal-Kombat-3-iOS-Recomp)** — la otra mitad de este proyecto.
- **[ermaccer](https://github.com/ermaccer)** — [UMK3IOS.MeshSetTool](https://github.com/ermaccer/UMK3IOS.MeshSetTool), la primera herramienta pública para el formato de mallas de este juego y la referencia contra la que se comprobó el lector de aquí.
- **[touchHLE](https://github.com/touchHLE/touchHLE)** — emulador de aplicaciones de iPhone OS, usado como referencia de comportamiento.
- **[Godot](https://godotengine.org/)**, **[Capstone](https://www.capstone-engine.org/)**, **[Ghidra](https://ghidra-sre.org/)**.

---

## Legal

*Ultimate Mortal Kombat 3* y todos sus assets son propiedad de sus respectivos
titulares. Este proyecto no está afiliado ni respaldado por Electronic Arts,
Warner Bros. Interactive Entertainment, NetherRealm Studios ni Midway Games.

El trabajo aquí es ingeniería inversa con fines de **interoperabilidad y
preservación**: hacer que un software que ya no funciona en ninguna plataforma
actual vuelva a funcionar, en hardware que sus dueños ya tienen. No se
redistribuye código ni datos del juego. Todo opera sobre una copia que el
usuario ya posee.

El código propio de este proyecto se publica bajo la [licencia MIT](LICENSE).
