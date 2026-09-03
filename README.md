# Offhand Screen View

Complemento para el mod **offhand** (fork de SFENCE / t-affeldt de `mcl_offhand`).
Muestra el item de la mano secundaria en pantalla, al estilo Minecraft, y se ve
**tanto en primera como en tercera persona**.

## El problema original

El icono viejo caía en `def.tiles[1]` y mostraba la textura del lado superior
**plana** (un `default:dirt_with_grass` se veía como un cuadrado de pasto),
mientras que en la mano principal el motor extruye un objeto 3D.

## Qué hace ahora

1. **Cubo 3D con movimiento.** Los bloques se dibujan con el modificador
   `[inventorycube` (el mismo renderizador 3D por software que usa el motor
   para el hotbar). Para que no parezca una imagen incrustada:
   - **gira** lentamente: se ciclan las cuatro rotaciones isométricas del cubo
     (`offhand_screen_spin`),
   - tiene una **sombra** suave detrás (`offhand_screen_shadow`),
   - **se balancea** al caminar (`offhand_screen_bob`).
2. **Posición de mano izquierda.** El icono va anclado abajo a la izquierda,
   grande (380 px por defecto), espejando la vista de la mano principal del
   motor. La posición es una *fracción de pantalla* (`pos_x`, `pos_y`), así
   funciona en cualquier resolución.
3. **Contador de items** en la esquina, como en Minecraft.
4. Opcionalmente **esconde el icono del mod base** junto al hotbar
   (`offhand_screen_hide_base_icon`, apagado por defecto: los dos quedan
   visibles).

## Por qué no es un objeto 3D de verdad en primera persona

- El motor renderiza **un solo** modelo de mano en primera persona (la
  principal); una segunda mano real sigue abierta como pedido al motor
  ([luanti#10345](https://github.com/luanti-org/luanti/issues/10345)).
- El item 3D que el mod `offhand` adjunta al hueso `Arm_Left` no se dibuja en
  primera persona salvo con `forced_visible = true`, y aun así el cliente no
  aplica la transformación del hueso al jugador local: queda flotando a los
  pies. Por eso se usa un elemento de HUD anclado a la pantalla, que es lo
  único que puede quedar "a la altura de la mano".
- En **segunda/tercera persona** el mod base ya muestra el item 3D en el brazo;
  el icono de este mod también se ve ahí (el servidor no puede saber en qué
  cámara estás). Si te molesta, poné `offhand_screen_show_icon = false` y
  quedás solo con el comportamiento del mod base.

## Ajustes

| Ajuste | Por defecto | Descripción |
| --- | --- | --- |
| `offhand_screen_icon_size` | `380` | Tamaño del icono en píxeles. |
| `offhand_screen_bg_padding` | `6` | Píxeles de fondo oscuro (si está activo). |
| `offhand_screen_pos_x` | `0.12` | Posición X, fracción del ancho (0..1). |
| `offhand_screen_pos_y` | `0.88` | Posición Y, fracción del alto (0..1). |
| `offhand_screen_show_icon` | `true` | Mostrar el icono de este mod. |
| `offhand_screen_show_background` | `false` | Fondo oscuro tipo ranura. |
| `offhand_screen_show_count` | `true` | Cantidad del stack en la esquina. |
| `offhand_screen_3d_icons` | `true` | Bloques como cubos 3D (si no, plano). |
| `offhand_screen_spin` | `true` | El cubo gira lentamente. |
| `offhand_screen_spin_period` | `1.6` | Segundos por vuelta completa. |
| `offhand_screen_shadow` | `true` | Sombra detrás del icono. |
| `offhand_screen_bob` | `true` | Balanceo al caminar. |
| `offhand_screen_hide_base_icon` | `false` | Esconder el icono del mod base. |

## API

```lua
offhand_screen_view.build_icon(itemname)         -- textura del primer frame
offhand_screen_view.build_icon_frames(itemname)  -- los 4 frames de rotación
offhand_screen_view.update(player)               -- refresca el HUD
offhand_screen_view.spin(player)                 -- avanza la rotación
offhand_screen_view.bob(player, clock)           -- aplica el balanceo
offhand_screen_view.hide_base_hud(player)        -- esconde el icono base
```

## Nota sobre el mod `offhand`

En el fork de **t-affeldt** la línea `textures:gsub("^%", "&")` usa un patrón
de Lua mal formado (`"^%"` en vez de `"%^"`) y lanza *malformed pattern*, por
lo que ahí el icono del mod base no llega a dibujarse para los bloques sin
`inventory_image`. En el fork de **SFENCE** está correcto. Este complemento no
depende de esa función: construye su propio icono.

## Tests

No hacen falta ni el motor ni un mundo: `tests/test_init.lua` carga el
`init.lua` real contra una API de `minetest`/`offhand` falsa y comprueba las
texturas generadas, los frames de rotación y los elementos HUD creados,
modificados y eliminados.

```sh
lua5.1 tests/test_init.lua     # o lua5.4, luajit, ...
```
