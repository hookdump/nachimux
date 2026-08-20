# nachimux

Una configuración de tmux pensada para sentirse como un navegador: proyectos como
**workspaces**, ventanas como **tabs** y paneles como **splits**. Usa el prefix estándar
de tmux: **`Ctrl-b`**.

La guía visual completa está en [tmux-guide.html](./tmux-guide.html).

## Empezar

```sh
# Dependencias principales (macOS)
brew install tmux gum fzf zoxide

# Desde este directorio
./nachimux setup
nachimux doctor
nachimux docs
```

`setup` enlaza el comando en `~/.local/bin`, agrega este perfil a `~/.tmux.conf`,
instala [TPM](https://github.com/tmux-plugins/tpm) y sus plugins, y recarga tmux si
ya está abierto. Termina con la barra funcionando. No reemplaza archivos ni enlaces
que no reconoce.

Si algo del paso de plugins falla, lo dice: abrí tmux y presioná `Ctrl-b`, soltá, y
después `I`.

Para deshacerlo:

```sh
nachimux uninstall           # quita el enlace y el bloque de ~/.tmux.conf
nachimux uninstall --purge   # además borra pines, listas recientes y el mute
```

`uninstall` solo toca lo que `setup` creó: un enlace que apunte a otro lado, o
configuración escrita a mano, los deja intactos. TPM, los plugins y este repo no se
tocan.

## El único concepto importante

Los atajos se escriben como `prefix p`. Eso significa:

1. Presiona `Ctrl-b`.
2. Suelta ambas teclas.
3. Presiona `p`.

`prefix p` abre una paleta buscable que **ejecuta** acciones. `prefix /` abre
`nachimux` en otro popup para **consultar y aprender** los atajos. Ambos leen el mismo
registro, por lo que las teclas y descripciones no pueden divergir.

## Comando `nachimux`

```text
nachimux                  busca cualquier atajo
nachimux split            abre la búsqueda filtrada por "split"
nachimux category         navega por categoría
nachimux all              imprime todos los atajos
nachimux prefix           explica cómo usar Ctrl-b
nachimux docs             abre la guía visual
nachimux doctor           revisa instalación, dependencias y prefix activo
nachimux setup            instala el enlace y activa el perfil
nachimux help             muestra la ayuda
```

También funcionan las opciones cortas existentes: `-c`, `-a`, `-p` y `-h`.

## Atajos para sobrevivir el primer día

| Acción | Teclas |
| --- | --- |
| Abrir la paleta | `prefix p` |
| Consultar todos los atajos | `prefix /` |
| Cambiar o crear workspace | `prefix w` |
| Nueva tab | `prefix t` |
| Split lado a lado | `prefix =` |
| Split arriba/abajo | `prefix -` |
| Moverse entre splits | `prefix h/j/k/l` |
| Zoom de un split | `prefix z` |
| Recargar la configuración | `prefix r` |
| Salir sin cerrar nada | `prefix d` |

## Archivos

- `tmux.spanish.conf`: configuración principal.
- `data/cheatsheet.tsv`: registro único de atajos, acciones y confirmaciones.
- `scripts/`: paleta, sonidos y la barra de estado.
- `test/smoke.sh`: arranca la config en un socket descartable con un cliente
  real y verifica que la barra realmente dibuje algo. tmux no falla en voz
  alta: un formato roto se dibuja como nada.
- `tmux-guide.html`: documentación visual autocontenida.

El perfil resuelve los scripts desde la ubicación real del repo, por lo que no depende
de que esté clonado en un directorio específico.

Las columnas del registro son `category`, `mode`, `keys`, `description`, `command` y
`confirm`. Si una fila tiene `command`, aparece también en la paleta ejecutable. Si
además tiene `confirm`, tmux pide confirmación antes de ejecutar una acción destructiva.

El perfil, el CLI y toda la documentación usan el estándar `C-b`, para que nunca haya
dos fuentes de verdad distintas.
