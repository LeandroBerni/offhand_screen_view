# Offhand Screen View

Complemento para el mod **offhand** (fork de SFENCE / t-affeldt de `mcl_offhand`).
Muestra el item de la mano secundaria en pantalla, al estilo Minecraft, y se ve
**tanto en primera como en tercera persona**.

## El problema que arregla

Antes el icono se construía así:

```lua
if def.inventory_image ... elseif def.tiles and def.tiles[1] then
    return get_tile_name(def.tiles[1])   -- <- textura plana