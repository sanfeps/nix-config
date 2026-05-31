# Plan de implementación media stack declarativo (Mullvad + Gluetun + Servarr + Seerr + Jellyfin)

> **Fecha:** 2026-05-31
>
> **Objetivo:** desplegar en `asgard` un stack de media totalmente declarativo en el repo `nix-config`, con todo el tráfico saliente del plano de adquisición detrás de `Mullvad` vía `Gluetun`, y con bootstrap idempotente por API para evitar configuración manual en las UIs.

---

## 1. Decisiones ya tomadas

- **Host del stack:** `asgard` (`192.168.1.54`).
- **Edge / ingress:** `bifrost` sigue siendo el único frontend con `AdGuard + Caddy + homepage`.
- **VPN elegida:** `Mullvad`.
- **Túnel VPN:** `WireGuard` (no OpenVPN).
- **Aislamiento:** usar `Gluetun` como gateway de red del plano de adquisición.
- **Objetivo funcional:** flujo completo `Seerr -> Sonarr/Radarr -> qBittorrent -> import -> Jellyfin`.
- **Bootstrap:** declarativo por API, no clics manuales.
- **No perseguir ahora:** OIDC, multiusuario fino, trackers privados/ratio tuning, port forwarding del proveedor VPN.

### Implicaciones de Mullvad

- Mullvad vale para el objetivo real: **todo el tráfico saliente del stack hacia Internet debe ir por la VPN**.
- **No hace falta port forwarding del proveedor** para ese objetivo.
- El stack seguirá funcionando sin eso; solo se renuncia a mejoras de conectividad entrante de BitTorrent.

---

## 2. Arquitectura propuesta

### Plano acquisition detrás de VPN

Estos servicios comparten el namespace de red de `gluetun`:

- `qbittorrent`
- `prowlarr`
- `sonarr`
- `radarr`
- `bazarr` opcional
- `lidarr` opcional
- `readarr` opcional
- `flaresolverr` opcional

### Plano LAN / playback fuera de VPN

Estos servicios no deben ir detrás de la VPN:

- `jellyfin`
- `seerr`
- `recyclarr`
- reconciler / bootstrap API

### Motivo de separar así

- `Jellyfin` es LAN-facing; meterlo detrás de la VPN no aporta valor.
- `Seerr` necesita ser cómodo de usar en LAN y solo orquesta requests; no necesita estar bajo VPN.
- El plano que sí debe ocultar su egress es el de indexers / trackers / descargas.

---

## 3. Layout de datos

Usar un root único bajo `/srv/media`, porque `/srv` ya persiste globalmente.

### Rutas host

- `/srv/media/data/media/movies`
- `/srv/media/data/media/tv`
- `/srv/media/data/media/music`
- `/srv/media/data/media/books`
- `/srv/media/data/downloads/torrents/movies`
- `/srv/media/data/downloads/torrents/tv`
- `/srv/media/data/downloads/torrents/music`
- `/srv/media/data/downloads/torrents/books`
- `/srv/media/state/gluetun`
- `/srv/media/state/qbittorrent`
- `/srv/media/state/prowlarr`
- `/srv/media/state/sonarr`
- `/srv/media/state/radarr`
- `/srv/media/state/bazarr`
- `/srv/media/state/lidarr`
- `/srv/media/state/readarr`
- `/srv/media/state/seerr`
- `/srv/media/state/jellyfin`
- `/srv/media/state/recyclarr`

### Rutas dentro de contenedores

Todo el plano media debe ver el mismo root:

- `/data/media/...`
- `/data/downloads/...`

Esto es importante para que `Sonarr/Radarr` hagan **hardlinks / atomic moves** correctamente y no conviertan imports en copias.

---

## 4. Layout de ficheros en el repo

Crear este subárbol:

- `hosts/asgard/services/media/default.nix`
- `hosts/asgard/services/media/storage.nix`
- `hosts/asgard/services/media/gluetun.nix`
- `hosts/asgard/services/media/qbittorrent.nix`
- `hosts/asgard/services/media/prowlarr.nix`
- `hosts/asgard/services/media/sonarr.nix`
- `hosts/asgard/services/media/radarr.nix`
- `hosts/asgard/services/media/jellyfin.nix`
- `hosts/asgard/services/media/seerr.nix`
- `hosts/asgard/services/media/recyclarr.nix`
- `hosts/asgard/services/media/bootstrap.nix`
- `hosts/asgard/services/media/state.nix`

Y luego:

- añadir `./media` a `hosts/asgard/services/default.nix`
- añadir rewrites / vhosts / tiles en `bifrost` cuando el stack local ya arranque en `asgard`

### Deliberadamente NO hacer de primeras

- no generalizar todavía a `modules/nixos/services/containers/*`
- no reutilizar el módulo genérico actual de `jellyfin`
- no esconder un `docker-compose` dentro de Nix

Primero hay que dejar el stack sólido y operable en `asgard`.

---

## 5. Puertos y exposición

### En `asgard`

Puertos locales previstos:

- `jellyfin`: `8096`
- `seerr`: `5055`
- `qbittorrent`: `8080`
- `prowlarr`: `9696`
- `sonarr`: `8989`
- `radarr`: `7878`
- `bazarr`: `6767`
- `lidarr`: `8686`
- `readarr`: `8787`

### Política de exposición

- `bifrost` reverse-proxy a `asgard`
- firewall en `asgard` restringido a `192.168.1.55` para los puertos de UI
- opcionalmente permitir también acceso desde tailnet `100.64.0.0/10` para administración

### DNS / Caddy / homepage en `bifrost`

Cuando llegue el momento:

- `jellyfin.lan.valgrindr.net`
- `seerr.lan.valgrindr.net`
- `qbittorrent.lan.valgrindr.net`
- `prowlarr.lan.valgrindr.net`
- `sonarr.lan.valgrindr.net`
- `radarr.lan.valgrindr.net`

En homepage:

- visibles para usuario final: `Jellyfin`, `Seerr`
- admin opcionales: `qBittorrent`, `Prowlarr`, `Sonarr`, `Radarr`

---

## 6. Diseño de Gluetun

### Enfoque

- `gluetun` será un contenedor `podman` normal
- los servicios del plano acquisition compartirán su namespace de red
- los puertos LAN se publicarán en `gluetun`

### Configuración esperada

- `Mullvad + WireGuard`
- `NET_ADMIN`
- `/dev/net/tun`
- `health server` activado para readiness
- `FIREWALL_OUTBOUND_SUBNETS=192.168.1.0/24,100.64.0.0/10`

### Secretos

En vez de 20 variables dispersas, usar un `wg0.conf` desde `sops.templates`, montado en el contenedor.

Nombre de secret propuesto:

- `media/mullvad-wg-conf`

### Importante

No usar el módulo host-global [hosts/common/core/mullvad-vpn.nix](/home/sanfe/nix-config/hosts/common/core/mullvad-vpn.nix) para este caso. Ese enfoque tuneliza el host, no el stack.

---

## 7. Servicios y rol de cada uno

### qBittorrent

- download client único
- categorías:
  - `radarr`
  - `sonarr`
  - `lidarr`
  - `readarr`
- save paths:
  - `radarr -> /data/downloads/torrents/movies`
  - `sonarr -> /data/downloads/torrents/tv`

### Prowlarr

- fuente única de indexers
- sincroniza hacia `Sonarr` y `Radarr`
- puede vivir completo detrás de la VPN

### Sonarr / Radarr

- root folders:
  - `Sonarr -> /data/media/tv`
  - `Radarr -> /data/media/movies`
- download client: `qBittorrent`
- import desde rutas consistentes bajo `/data`

### Seerr

- interfaz de request
- conecta a:
  - `Jellyfin`
  - `Sonarr`
  - `Radarr`
- debe quedar accesible de forma cómoda desde LAN

### Jellyfin

- servidor de reproducción
- ve solo `/data/media`
- fuera de VPN

### Recyclarr

- empuja config declarativa de:
  - quality profiles
  - custom formats
  - naming
  - media management fino
- objetivo: evitar meter toda esa lógica a mano en el reconciler propio

---

## 8. Bootstrap declarativo por API

La pieza central será un reconciler idempotente.

### Idea

- un attrset Nix describe el **estado deseado**
- Nix lo renderiza a `JSON` bajo `/run/media-stack/desired-state.json`
- un `systemd oneshot` espera a que todo esté arriba y luego converge el estado por API

### Archivo fuente de estado

- `hosts/asgard/services/media/state.nix`

### Servicio

- `media-bootstrap.service`

### Timer opcional

- `media-bootstrap.timer`

Útil para re-converger periódicamente después de cambios manuales o upgrades.

### Qué debe cubrir el reconciler propio

- `qBittorrent`
  - categorías
  - save paths
  - preferencias mínimas de WebUI
- `Prowlarr`
  - aplicaciones (`Sonarr`, `Radarr`)
  - indexers
- `Sonarr/Radarr`
  - root folders
  - download client
  - media management básico si no lo cubre `Recyclarr`
- `Seerr`
  - conexión a `Jellyfin`
  - conexiones a `Sonarr` y `Radarr`
  - defaults de request
- `Jellyfin`
  - bibliotecas
  - usuario admin inicial si hace falta

### Qué debe delegarse a Recyclarr

- quality profiles
- custom formats
- naming
- media naming / release profiles

No reinventar eso en shell.

---

## 9. Secretos a añadir

En `hosts/asgard/secrets.yaml`:

- `media/mullvad-wg-conf`
- `media/qbittorrent-password`
- `media/prowlarr-api-key`
- `media/sonarr-api-key`
- `media/radarr-api-key`
- `media/seerr-api-key`
- `media/jellyfin-admin-password`

Opcionales más adelante:

- `media/bazarr-api-key`
- `media/lidarr-api-key`
- `media/readarr-api-key`
- `media/flaresolverr-*`

### Nota importante

Siempre que sea posible, fijar las API keys declarativamente por variables/config para que el reconciler no dependa de “leer la key de la UI”.

---

## 10. Fases de implementación

### Fase 1 — storage y plumbing base

Objetivo: preparar rutas persistidas y el nuevo subárbol de módulos.

Tareas:

- crear `hosts/asgard/services/media/default.nix`
- crear `storage.nix`
- importar `./media` desde `hosts/asgard/services/default.nix`
- crear todas las rutas bajo `/srv/media`

### Fase 2 — Gluetun + qBittorrent

Objetivo: primer slice funcional detrás de Mullvad.

Tareas:

- `gluetun.nix`
- `qbittorrent.nix`
- secretos de Mullvad y password
- comprobar:
  - `qBittorrent` accesible desde LAN
  - tráfico saliente sale por VPN
  - si `gluetun` cae, `qbittorrent` pierde egress

### Fase 3 — Prowlarr + Sonarr + Radarr

Objetivo: plano acquisition completo arrancando detrás de VPN.

Tareas:

- `prowlarr.nix`
- `sonarr.nix`
- `radarr.nix`
- root folders y mounts consistentes
- publicar UIs vía `gluetun`

### Fase 4 — Jellyfin + Seerr

Objetivo: completar el flujo visible al usuario.

Tareas:

- `jellyfin.nix`
- `seerr.nix`
- mounts de librerías
- `bifrost`:
  - DNS rewrites
  - Caddy handles
  - homepage tiles

### Fase 5 — Recyclarr + estado declarativo

Objetivo: quitar el máximo de config manual en `Sonarr/Radarr`.

Tareas:

- `recyclarr.nix`
- definir config declarativa base

### Fase 6 — reconciler API

Objetivo: full declarative de verdad.

Tareas:

- `state.nix`
- `bootstrap.nix`
- script o programa reconciler
- `systemd oneshot`
- timer opcional

### Fase 7 — validación E2E

Objetivo: comprobar el flujo completo.

Escenario:

1. abrir `Seerr`
2. pedir una peli
3. verificar que entra en `Radarr`
4. verificar que `Radarr` la manda a `qBittorrent`
5. verificar descarga
6. verificar import a `/data/media/movies`
7. verificar aparición en `Jellyfin`

---

## 11. Orden recomendado para mañana

No intentar hacerlo todo de una.

### Slice 1

- `storage.nix`
- `gluetun.nix`
- `qbittorrent.nix`

**Objetivo de parada:** un `qBittorrent` funcional detrás de Mullvad, visible desde LAN.

### Slice 2

- `prowlarr.nix`
- `sonarr.nix`
- `radarr.nix`

**Objetivo de parada:** el plano acquisition arranca entero y puede verse por UI.

### Slice 3

- `jellyfin.nix`
- `seerr.nix`
- wiring en `bifrost`

**Objetivo de parada:** UIs finales accesibles por `*.lan.valgrindr.net`.

### Slice 4

- `recyclarr.nix`
- `state.nix`
- `bootstrap.nix`

**Objetivo de parada:** bootstrap declarativo sin clics.

---

## 12. Checklist de validación por fase

### Red / VPN

- `gluetun` healthy
- `curl ifconfig.me` desde un contenedor detrás de Gluetun devuelve IP de Mullvad
- sin `gluetun`, no hay salida a Internet desde servicios `viaVpn`

### Paths

- descargas caen en `/data/downloads/...`
- imports van a `/data/media/...`
- no hay copias gigantes innecesarias

### Apps

- `Prowlarr` ve indexers
- `Sonarr/Radarr` ven `qBittorrent`
- `Seerr` ve `Jellyfin`, `Sonarr`, `Radarr`
- `Jellyfin` ve bibliotecas

### E2E

- request de peli desde `Seerr`
- descarga se ejecuta
- import final correcto
- item visible en `Jellyfin`

---

## 13. Riesgos / dudas pendientes

### 13.1. ¿Meter `Sonarr/Radarr` detrás de la VPN o no?

Decisión por ahora: **sí**, porque el usuario quiere que “todo el tráfico del stack saliente hacia Internet” vaya por la VPN.

Si da demasiada fricción, alternativa:

- mantener `qBittorrent + Prowlarr` detrás de VPN
- sacar `Sonarr/Radarr` fuera

Pero esa NO es la opción objetivo inicial.

### 13.2. Bootstrap de Jellyfin

Jellyfin es la pieza menos naturalmente declarativa.

Si la API para bibliotecas/usuarios complica demasiado el primer pase:

- tolerar bootstrap mínimo una sola vez para Jellyfin
- mantener full declarative en el resto

Solo usar esta salida si el coste de automatizar Jellyfin se dispara.

### 13.3. ¿Shell o programa para el reconciler?

Preferencia:

- si el alcance es pequeño, `bash + curl + jq`
- si crece rápido, pasar pronto a `python`

No meter un “megabash” inmantenible.

---

## 14. Criterio de éxito final

Se considerará terminado cuando:

- `asgard` aloje el stack completo
- todo el plano acquisition salga por Mullvad vía Gluetun
- `bifrost` exponga las UIs por `*.lan.valgrindr.net`
- el flujo `Seerr -> Radarr/Sonarr -> qBittorrent -> Jellyfin` funcione E2E
- no haga falta configurar manualmente las relaciones principales entre apps tras un rebuild limpio

---

## 15. Primeros ficheros a tocar mañana

En este orden:

1. `hosts/asgard/services/default.nix`
2. `hosts/asgard/services/media/default.nix`
3. `hosts/asgard/services/media/storage.nix`
4. `hosts/asgard/services/media/gluetun.nix`
5. `hosts/asgard/services/media/qbittorrent.nix`
6. `hosts/asgard/secrets.yaml`

Si al terminar esos seis puntos `qBittorrent` no está detrás de Mullvad y accesible desde LAN, no pasar aún a `Prowlarr/Sonarr/Radarr`.
