# Decisiones de ScreenZones

ScreenZones divide cada pantalla en zonas fijas que se comportan como monitores independientes. Tiene dos apps: un script de KWin con un widget de bandeja para KDE Plasma 6, en `linux/`, y una app de barra de menú para macOS, en `macos/`. Las dos hacen lo mismo, se llaman igual y dicen lo mismo. Cada diferencia está escrita en su sección, como "Solo en Linux" o "Solo en macOS", con su razón. Ante una diferencia nueva gana la versión más correcta, y se lleva a la otra plataforma.

## Objetivo

Trabajar en una pantalla grande como si fueran varias. Cada ventana pertenece a una zona, conserva su propio tamaño dentro de ella y nunca invade otra. Cada zona tiene su barra de pestañas con sus ventanas.

## Nombre

El nombre visible es **ScreenZones**; el repositorio es `screen-zones`. El id es `local.screenzones` en las dos plataformas:

- **Linux:** el script de KWin y el widget de bandeja son `local.screenzones`, igual que el icono instalado. La acción del menú en los atajos globales se llama "ScreenZones Menu".
- **macOS:** el bundle es `local.screenzones`, el agente de inicio de sesión es `local.screenzones.login` y el aviso que cierra la app es `local.screenzones.quit`.

## Prioridad

Consumo mínimo de recursos, con la RAM por delante. En Linux el script corre dentro de KWin, así que cada ventana superpuesta y cada temporizador pesan en el compositor. En macOS los paneles dibujan solo en sRGB, porque cualquier otro espacio de color hace que CoreGraphics guarde tablas de conversión de cientos de KB.

## Equipos

- **Linux:** CachyOS con KDE Plasma 6.8 en Wayland.
- **macOS:** Mac con Apple Silicon y macOS 27.

## Alcance

ScreenZones existe por lo que el sistema no da. Ni el mosaico de KDE (Meta+T), ni scripts como KZones, PlasmaZones o Polonium, ni el mosaico de macOS ofrecen:

- Pestañas por zona.
- Ventanas contenidas en su zona, con su propio tamaño.
- Memoria de la última zona de cada app, por cada conjunto de pantallas conectadas.

Sin atajos de teclado: todo se hace con el mouse, desde el icono y desde las barras. En Linux la acción "ScreenZones Menu" queda registrada sin tecla, solo para que el widget de bandeja abra el menú.

## Stack

### Linux

Script de KWin en QML y JavaScript, cargado en el proceso de KWin, más un widget de bandeja en QML. En Wayland solo el compositor puede mover las ventanas de otras apps, así que no hay un programa aparte. El widget abre el menú del script a través de kglobalaccel, el único canal de plasmashell hacia un script de KWin.

### macOS

Swift 6 con AppKit, compilado con SwiftPM. Las ventanas se leen y se mueven con la API de Accesibilidad. Dos funciones privadas cubren lo que la API pública no da: `_AXUIElementGetWindow`, que relaciona una ventana de Accesibilidad con su número de ventana, y `CGSCopyManagedDisplaySpaces`, que dice qué pantallas muestran un Space de pantalla completa.

## Zonas y disposiciones

- Cada pantalla se activa por separado con "Usar zonas en esta pantalla" y muestra una disposición: un conjunto de zonas con nombre, guardadas como fracciones de la pantalla.
- "Una columna" es la única disposición incluida; nunca se guarda ni se edita. Una nueva se llama "Disposición N" y los nombres son únicos sin distinguir mayúsculas.
- Las zonas se nombran con letras en orden de lectura. Si una regla apunta a una letra que la disposición no tiene, se usa la anterior más cercana: C cae en B con dos columnas.
- Con "Bloquear el tamaño de las zonas", las zonas cambian solo en el editor: cambiar el tamaño de una ventana nunca mueve una división. Sin el bloqueo, cambiar el tamaño de una ventana que llena su zona, tomándola a menos de 12 px de una división, mueve esa división y cambia solo esa pantalla: la disposición queda "(sin guardar)" hasta guardarla en el editor o descartar los cambios.
- Guardar en el editor cambia la disposición en todas las pantallas que la usan. Eliminarla las devuelve a "Una columna".

## Editor

Ocupa el área de las zonas de la pantalla y se titula con el nombre de la disposición. Cada zona muestra "Zona: ancho × alto px · ancho % × alto %" y su tamaño físico, y se puede dividir en columnas o filas, o eliminar: sus vecinas de un lado completo toman su espacio. Las líneas entre zonas se arrastran y quedan donde se sueltan, sin imán. Guardar o Return guardan; Cancelar o Esc cancelan.

- **Solo en Linux:** un clic fuera del editor o la activación de cualquier ventana lo cancela. KWin entrega el teclado a una ventana propia solo si es un menú emergente, y un menú emergente se cierra así.

## Barras de pestañas

- Cada zona tiene su barra en el lado que se elija: el general, el de su pantalla o el suyo propio, en ese orden de prioridad. Arriba o abajo mide 22 px; a la izquierda o a la derecha, 170 px.
- "Compacta": en una barra lateral, la columna mide 30 px, solo con iconos, y se abre a 170 px sobre la ventana 0,15 s después de que entra el puntero; se cierra en cuanto sale, salvo mientras se arrastra una pestaña. En una fila, cada pestaña, salvo la de adelante, se reduce a su icono.
- Cada pestaña muestra el icono de la app, de 16 px, y el título de la ventana; sin título, el nombre de la app. Las minimizadas se ven atenuadas.
- Un clic activa la ventana. Arrastrar una pestaña dentro de su barra la reordena; soltarla en otra zona lleva la ventana a la zona bajo el puntero.
- La pestaña activa y la pestaña bajo el puntero llevan los botones de cerrar, minimizar y llenar la zona o volver al tamaño anterior, que actúan sobre su propia ventana. Aparecen solo si la pestaña muestra su título y es lo bastante ancha; una pestaña minimizada o reducida a su icono no los lleva, y para esas queda el clic derecho.
- Un clic en la letra de la zona muestra su tamaño, su tamaño físico y su porcentaje de la pantalla.
- **Solo en macOS, botones rojo, amarillo y verde:** son los de cualquier ventana de macOS. En Linux los botones usan los iconos `window-*` del tema, como las ventanas de Plasma.
- **Capa de las barras:** en Linux van por encima de todo y se recortan donde otra ventana las tapa, porque KWin pone cada ventana propia de un script en su capa superior y no permite bajarla. En macOS son paneles normales enviados detrás de todas las ventanas; la columna compacta, mientras está abierta, sube por encima de ellas, para que activar una ventana desde una pestaña no la tape.
- **Cierre del tamaño de la zona:** en macOS se cierra con cualquier clic fuera de la letra. En Linux se cierra al activar otra ventana, al empezar un gesto o al cambiar la geometría, porque un script de KWin no ve los clics de las demás ventanas.

## Menús

El icono abre el menú principal:

- Una entrada por pantalla, "pantalla — disposición", con: Usar zonas en esta pantalla; las disposiciones; Barra de pestañas (Como las demás, Arriba, Abajo, Izquierda o Derecha); la disposición actual, con Editar…, Descartar los cambios sin guardar, Renombrar… y Eliminar…; y Nueva disposición….
- Barra de pestañas: los cuatro lados y Compacta.
- Mostrar bordes de las zonas.
- Bloquear el tamaño de las zonas, Imantar las ventanas a su zona, Pantalla completa dentro de la zona (solo en Linux) y Apps libres.
- Pausar o Reanudar.

El clic derecho en la letra de una zona o en una parte vacía de su barra abre el mismo menú, que empieza con "Zona X · pantalla" y "Barra de esta zona" (Como la pantalla o uno de los cuatro lados). El clic derecho en una pestaña abre: Maximizar en la zona o Volver al tamaño anterior, Centrar en la zona, Minimizar, Cerrar, Barra de la zona X, Abrir *app* en (La última zona que usó, o una zona de cada pantalla) y *App* ignora las zonas.

Eliminar una disposición pide confirmación, y crear o renombrar una pide el nombre; un nombre vacío deja el propuesto. Esc cancela.

- **Nombre de la pantalla:** el actual, nunca uno guardado. En Linux es "conector · modelo", porque Plasma no da otro nombre; en macOS, el nombre que da el sistema.
- **Nombre de la app:** en macOS, el nombre que da el sistema. En Linux, el último tramo del id de la app con mayúscula inicial ("Dolphin" para `org.kde.dolphin`), porque KWin no expone el nombre del archivo `.desktop`.
- **Opciones excluyentes:** la elegida lleva una marca en las dos. En Linux se ve como casilla y no como botón de opción, porque los menús de `Qt.labs.platform` dentro de KWin no pasan los grupos excluyentes a `QMenu`.
- **Solo en Linux, el menú se vuelve a abrir:** si una ventana que se cierra al perder el foco, como el lanzador de Plasma, lo cierra antes de 1 s, el menú se abre de nuevo en el puntero. KWin cierra cualquier menú emergente al activarse otra ventana.
- **Solo en macOS, el icono en pausa:** se dibuja con contornos en pausa o sin el permiso de Accesibilidad. En Linux el script de KWin no tiene cómo avisarle al widget de bandeja; en pausa, las barras desaparecen y el menú ofrece Reanudar.
- **Solo en macOS, "Esperando el permiso de Accesibilidad":** el menú lo muestra hasta que el permiso se concede.

## Colocación

- Una ventana pide su tamaño preferido, limitado a su zona: el que tenía al entrar, después el que le deja cada cambio de tamaño del usuario o de la app.
- Un borde compartido con otra zona es una pared, y también un borde de la pantalla con otra pantalla al lado. Más allá de otro borde de la pantalla, la ventana se queda donde se suelta mientras una parte siga en la zona. Nunca queda debajo de su barra.
- Con "Imantar las ventanas a su zona" cada ventana queda entera dentro de su zona; activarlo o desactivarlo recoloca todas.
- Una ventana más grande que su zona se sale por el borde de la pantalla que toca la zona, lejos de su barra.
- Maximizar llena la zona, y volver al tamaño anterior lo recupera. Un mosaico del sistema también termina con la ventana llenando su zona.
- **Solo en macOS, mosaico por teclado:** el mosaico por arrastre llena la zona; el del teclado o del menú Ventana se trata como cualquier cambio de tamaño, porque macOS no lo distingue de un cambio que hace la propia app.
- Una ventana nueva va a la regla de su app; si no hay, a la última zona de la app para el conjunto de pantallas conectadas; si no, a la zona A de la pantalla donde aparece.
- Las apps libres no se administran.
- **Solo en Linux, "Pantalla completa dentro de la zona":** activado, una ventana a pantalla completa llena su zona entera, barra incluida; desactivado, ocupa la pantalla. En macOS una ventana a pantalla completa ocupa la pantalla en su propio Space y ScreenZones no la mueve hasta que sale, porque macOS no da otro tamaño a la pantalla completa, y una app sacada de ella deja también su propio modo de pantalla completa: un video vuelve a la página.
- Al cambiar las pantallas se abre una espera de 3 s en la que nada se suelta ni se registra; al terminar, todo vuelve a su zona.
- Cada ventana guarda su pantalla, zona, tamaño preferido y si llenaba la zona un segundo después de cada cambio, y lo recupera si ScreenZones se reinicia.

## Ajustes

| Ajuste | Por defecto |
|---|---|
| Barra de pestañas | Arriba |
| Compacta | No |
| Mostrar bordes de las zonas | Sí |
| Bloquear el tamaño de las zonas | Sí |
| Imantar las ventanas a su zona | No |
| Pantalla completa dentro de la zona (solo en Linux) | Sí |
| Apps libres | Ninguna |

La pausa no se guarda: ScreenZones siempre arranca activo.

## Icono

El maestro es `assets/icon/AppIcon.svg`: una zona azul alta y dos grises sobre fondo oscuro. El icono de la bandeja o de la barra de menú repite las tres zonas a 18 px.

## Formato

Tamaños como "1920 × 1080 px" y porcentajes como "50 %", con espacios. El tamaño físico multiplica el tamaño por la escala de la pantalla.

## Colores

| Uso | Color |
|---|---|
| Fondo de la barra | `#121c38` |
| Pestaña | `#24334f` |
| Pestaña activa y zona azul del icono | `#386bd1` |
| Letra de la zona | `#8c9ec2`, seminegrita |
| Líneas entre zonas | `#6b6b6b` |

## Permisos

- **Linux:** ninguno. El script corre dentro de KWin.
- **macOS:** Accesibilidad. macOS ata el permiso a la firma: si el llavero tiene el certificado "Nico Local", la app se firma con él y el permiso sobrevive a cada compilación; si no, la firma es ad-hoc y cada compilación lo pide otra vez.

## Instalación

### Linux

El instalador agrega el script de KWin y el widget, activa el script para cada inicio de sesión y lo carga al momento; el widget aparece solo en la bandeja. Desinstalar quita los dos paquetes, el icono y la acción "ScreenZones Menu". La configuración queda en `~/.config/screenzonesrc`.

### macOS

La app se compila en el propio Mac y se copia a `~/Applications`. El agente `local.screenzones.login` la abre al iniciar sesión. Desinstalar quita la app y el agente; los ajustes quedan en los de `local.screenzones`.

## Fuentes de datos

### Linux

La API de scripts de KWin: las ventanas, sus señales y su geometría; el área de cada pantalla sin los paneles; y las salidas con su fabricante, modelo y número de serie, que identifican cada pantalla.

### macOS

La API de Accesibilidad para leer y mover ventanas, `CGWindowListCopyWindowInfo` para saber qué ventanas están en pantalla, un `CGEventTap` para los clics, y `NSScreen` con el UUID de cada pantalla, que la identifica sin depender de su posición.
