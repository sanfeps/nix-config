# Plan de implementación Authentik (SSO declarativo cross-host)

> **Objetivo:** un único punto de autenticación (`auth.lan.valgrindr.net`) que cubra todos los `*.lan.valgrindr.net` servicios — independientemente del host donde corra el backend — vía `forward_auth` en el Caddy edge de bifrost. Configuración 100% declarativa (Blueprints YAML + Nix). Bootstrap del admin user desde sops, sin click-through manual.
>
> **No incluye** (fuera de scope inicial): LDAP outpost, RADIUS, SCIM, federación cross-realm, MFA hardware. Si en el futuro hace falta, son extensiones aditivas.

---

## Índice

1. [Pre-requisitos y decisiones de arquitectura](#0-pre-requisitos-y-decisiones-de-arquitectura)
2. [Fase 1 — Módulo Podman + Postgres + Redis](#fase-1--módulo-podman--postgres--redis)
3. [Fase 2 — Sops secrets + bootstrap del admin](#fase-2--sops-secrets--bootstrap-del-admin)
4. [Fase 3 — Edge wiring en bifrost (Caddy, DNS, homepage)](#fase-3--edge-wiring-en-bifrost-caddy-dns-homepage)
5. [Fase 4 — Caddy snippet `forward_auth` reutilizable](#fase-4--caddy-snippet-forward_auth-reutilizable)
6. [Fase 5 — Blueprints declarativos desde Nix](#fase-5--blueprints-declarativos-desde-nix)
7. [Fase 6 — Integración por aplicación (incremental)](#fase-6--integración-por-aplicación-incremental)
8. [Fase 7 — Bypass de LAN durante rollout](#fase-7--bypass-de-lan-durante-rollout)
9. [Validación end-to-end](#validación-end-to-end)
10. [Recovery cheats](#recovery-cheats)

---

## 0. Pre-requisitos y decisiones de arquitectura

**¿Dónde corre Authentik?** En **asgard**:
- Reutiliza el Postgres compartido (Firefly + Immich + ahora Authentik); evita un segundo motor de DB.
- asgard tiene CPU/RAM holgadas; bifrost es la red, mantenerlo ligero.
- Coste cross-host: bifrost Caddy hace `forward_auth` a `192.168.1.54:9000` (~1 ms en LAN). Aceptable.

**¿Por qué contenedor y no módulo NixOS nativo?** No hay módulo NixOS oficial para Authentik. La imagen oficial (`ghcr.io/goauthentik/server`) está bien mantenida y soporta blueprints declarativos out of the box. Mismo patrón que Ghostfolio + headplane: `modules/nixos/services/containers/authentik.nix`.

**¿Authelia o Authentik?** Authentik. Razones:
- Blueprints YAML declarativos = encajan con la filosofía Nix (render desde `pkgs.formats.yaml.generate`).
- Soporte OIDC más maduro que Authelia (mejor con Immich, Grafana, Nextcloud, ...).
- Embedded outpost: el propio Authentik server expone el endpoint `/outpost.goauthentik.io/auth/caddy` que Caddy `forward_auth` consume directamente. Cero piezas extra.
- Tradeoff aceptado: ~500 MB RAM + Postgres + Redis vs los ~80 MB de Authelia. Asgard puede.

**Topología final**:

```
Cliente LAN
   │  https://<svc>.lan.valgrindr.net
   ▼
bifrost (Caddy edge, TLS termination)
   │  1. forward_auth → asgard:9000/outpost.goauthentik.io/auth/caddy
   │     - 200 OK + cabeceras X-Authentik-* → continúa
   │     - 302 → redirige al login en https://auth.lan.valgrindr.net
   │  2. reverse_proxy <host>:<port> (asgard u otro)
   ▼
backend del servicio (firefly/immich/etc.)
   - app con OIDC: consume X-Authentik-* headers o redirige a auth.lan...
   - app sin OIDC: ve un request autenticado por forward_auth + su propio login
```

**Persistence**: blueprints en `/var/lib/authentik/blueprints/local/*.yaml` (generados por Nix), media en `/var/lib/authentik/media`, certs en `/var/lib/authentik/certs`. Postgres data ya está cubierto por la persistencia existente del Postgres compartido.

**Cobertura cross-host gratis**: como bifrost es el único punto de ingress para `*.lan.valgrindr.net`, cualquier servicio nuevo (en asgard, midgard accesible vía tailnet, o futuro host) se gatea automáticamente añadiendo un handle a `caddy.nix` con `import authentik_auth`. No hay nada que configurar en el host del backend.

---

## Fase 1 — Módulo Podman + Postgres + Redis

**Archivo:** `modules/nixos/services/containers/authentik.nix`

Estructura del módulo, replicando el patrón de Ghostfolio (`hosts/asgard/services/finances/ghostfolio.nix`):

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.containers.authentik;
  port = 9000;
  imageTag = "2024.10.5";  # pin
in {
  options.services.containers.authentik = {
    enable = lib.mkEnableOption "Authentik SSO";
    # ... opciones para custom blueprints dir, externalUrl, etc.
  };

  config = lib.mkIf cfg.enable {
    # Postgres role + DB (reusa el motor compartido en asgard).
    services.postgresql = {
      ensureDatabases = ["authentik"];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
      # Necesita auth via TCP+scram (el container no llega al socket peer).
      authentication = lib.mkAfter ''
        host authentik authentik 127.0.0.1/32 scram-sha-256
      '';
    };

    # Redis dedicado (socket interno al container, sin exponer).
    # Authentik server + worker comparten el mismo redis del compose oficial.
    # Lo más simple: redis dentro del propio pod.

    virtualisation.oci-containers.containers = {
      authentik-redis = {
        image = "docker.io/redis:alpine";
        cmd = ["--save" "60" "1" "--loglevel" "warning"];
        extraOptions = ["--network=host"];
      };

      authentik-server = {
        image = "ghcr.io/goauthentik/server:${imageTag}";
        cmd = ["server"];
        environmentFiles = [config.sops.templates."authentik-env".path];
        environment = {
          AUTHENTIK_REDIS__HOST = "127.0.0.1";
          AUTHENTIK_POSTGRESQL__HOST = "127.0.0.1";
          AUTHENTIK_POSTGRESQL__USER = "authentik";
          AUTHENTIK_POSTGRESQL__NAME = "authentik";
          AUTHENTIK_LISTEN__HTTP = "127.0.0.1:9000";
          AUTHENTIK_LISTEN__HTTPS = "127.0.0.1:9443";
        };
        volumes = [
          "/var/lib/authentik/media:/media"
          "/var/lib/authentik/certs:/certs"
          "/var/lib/authentik/blueprints:/blueprints/local:ro"
        ];
        extraOptions = ["--network=host"];
      };

      authentik-worker = {
        image = "ghcr.io/goauthentik/server:${imageTag}";
        cmd = ["worker"];
        environmentFiles = [config.sops.templates."authentik-env".path];
        environment = { /* mismas vars que server */ };
        volumes = [ /* mismos mounts */ ];
        extraOptions = ["--network=host"];
      };
    };

    # Pattern-B firewall: solo bifrost llega a :9000.
    networking.firewall.extraCommands = ''
      iptables -I nixos-fw -p tcp --dport ${toString port} -s 192.168.1.55 -j nixos-fw-accept
    '';

    environment.persistence."${config.hostSpec.persistFolder}".directories = [
      {
        directory = "/var/lib/authentik";
        user = "root";  # los containers corren root; ajustar si pasamos a rootless
        group = "root";
        mode = "0700";
      }
    ];
  };
}
```

**Wire-up**: export en `modules/nixos/default.nix` (`authentik = import ./services/containers/authentik.nix;`), enable en `hosts/asgard/services/default.nix` con `services.containers.authentik.enable = true;`.

---

## Fase 2 — Sops secrets + bootstrap del admin

**Secrets nuevos** (`hosts/asgard/secrets.yaml`):

```yaml
authentik/secret-key:          # base64 32 bytes — generar con `openssl rand -base64 32`
authentik/postgres-password:   # contraseña para el rol postgres `authentik`
authentik/bootstrap-password:  # admin akadmin, primera vez
authentik/bootstrap-token:     # API token largo para reconciler / blueprints
```

**Template sops** (en `authentik.nix`):

```nix
sops.secrets = {
  "authentik/secret-key" = {};
  "authentik/postgres-password" = {};
  "authentik/bootstrap-password" = {};
  "authentik/bootstrap-token" = {};
};

sops.templates."authentik-env" = {
  content = ''
    AUTHENTIK_SECRET_KEY=${config.sops.placeholder."authentik/secret-key"}
    AUTHENTIK_POSTGRESQL__PASSWORD=${config.sops.placeholder."authentik/postgres-password"}
    AUTHENTIK_BOOTSTRAP_PASSWORD=${config.sops.placeholder."authentik/bootstrap-password"}
    AUTHENTIK_BOOTSTRAP_TOKEN=${config.sops.placeholder."authentik/bootstrap-token"}
  '';
  mode = "0400";
  restartUnits = ["podman-authentik-server.service" "podman-authentik-worker.service"];
};
```

**Reconciler para el rol Postgres** (`postgres-authentik-init.service`, oneshot): rellena la contraseña del rol `authentik` desde sops cada deploy, ANTES de que el container arranque (el mismo patrón que Firefly / Ghostfolio). `ALTER ROLE authentik WITH PASSWORD :pwd` vía `psql -h /run/postgresql`.

**Resultado en primer boot**: Authentik arranca, ve `AUTHENTIK_BOOTSTRAP_*`, crea el user `akadmin` con esa password + un API token con valor exacto del sops. A partir de ahí los blueprints pueden usar el token para operaciones idempotentes.

---

## Fase 3 — Edge wiring en bifrost (Caddy, DNS, homepage)

**`hosts/bifrost/services/caddy.nix`** (dentro del wildcard vhost):

```caddy
@auth host auth.lan.valgrindr.net
handle @auth {
  reverse_proxy 192.168.1.54:9000
}
```

**`hosts/bifrost/services/dns.nix`** (añadir rewrite):

```nix
{ domain = "auth.${lanZone}"; answer = bifrostIp; enabled = true; }
```

**`hosts/bifrost/services/homepage.nix`** (nuevo tile en "Edge (bifrost)" o nuevo grupo "Auth"):

```nix
{
  "Authentik" = {
    href = "https://auth.lan.valgrindr.net";
    description = "SSO + identity";
    icon = "authentik.png";
  };
}
```

Despliegue: asgard → bifrost. Tras esto `https://auth.lan.valgrindr.net` muestra la pantalla de login con `akadmin` + la password del sops.

---

## Fase 4 — Caddy snippet `forward_auth` reutilizable

El truco para que "añadir un servicio nuevo" sea trivial es definir una vez la lógica de `forward_auth` como **snippet** Caddy y reusarla en cada handle. En `hosts/bifrost/services/caddy.nix` (al nivel del `globalConfig` o como bloque arriba del vhost):

```caddy
(authentik_auth) {
  forward_auth 192.168.1.54:9000 {
    uri /outpost.goauthentik.io/auth/caddy
    copy_headers X-Authentik-Username X-Authentik-Groups X-Authentik-Email \
                 X-Authentik-Name X-Authentik-Uid X-Authentik-Jwt \
                 X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost \
                 X-Authentik-Meta-Provider X-Authentik-Meta-App \
                 X-Authentik-Meta-Version
    trusted_proxies private_ranges
  }
}
```

Y cada handle protegido pasa a verse así:

```caddy
@firefly host firefly.lan.valgrindr.net
handle @firefly {
  import authentik_auth
  reverse_proxy 192.168.1.54:80
}
```

**El cambio mecánico** que añade SSO a cualquier servicio existente es **una línea**: `import authentik_auth` dentro del handle. Por eso "funciona para cualquier app o host" sale natural — el ingress siempre es bifrost.

**Excepciones a vigilar**:
- Endpoints API que necesitan token de servicio (Sonarr/Radarr → Prowlarr sync, Seerr → *arrs): esos requests cross-service llevan `X-Api-Key`, NO un login de Authentik. Si los metes detrás de `forward_auth` los romperás. Solución: `forward_auth` solo sobre los hosts donde quieres login humano. Para los APIs entre servicios, mantén los handles directos como ahora.
  - En la práctica: usa nombres distintos para las APIs. Ej. `sonarr.lan.valgrindr.net` (UI, con SSO) vs `sonarr-api.lan.valgrindr.net` (API, sin SSO). O simplemente excluye los paths `/api/*` con un `@api path /api/*` matcher.
- Webhooks externos entrantes (TMDb → Seerr, …): mismo problema, los webhooks no llevan login. Path-based exclusion.

---

## Fase 5 — Blueprints declarativos desde Nix

Authentik aplica YAMLs en `/blueprints/local/` al arrancar (y en cada restart) de forma idempotente: si el objeto existe lo actualiza, si no lo crea. Esto encaja con el patrón Nix: rendereamos los blueprints desde atributos.

**En `authentik.nix`** (o un sub-módulo dedicado `authentik-blueprints.nix`):

```nix
let
  yamlFormat = pkgs.formats.yaml {};

  # Esquema base: un blueprint declara entities con identificadores estables (slug, name).
  mkBlueprint = name: entries: {
    version = 1;
    metadata.name = name;
    entries = entries;
  };

  blueprints = {
    "00-default-flow" = mkBlueprint "default-authentication-flow" [
      # ... default authentication flow, stages, prompt
    ];

    "10-application-firefly" = mkBlueprint "firefly" [
      {
        model = "authentik_providers_oauth2.oauth2provider";
        identifiers.name = "Firefly III";
        attrs = {
          authorization_flow = "default-provider-authorization-implicit-consent";
          client_type = "confidential";
          client_id = "firefly";
          # client_secret se genera y se inyecta vía sops template (no en el blueprint).
          redirect_uris = "https://firefly.lan.valgrindr.net/oauth/callback";
          # ...
        };
      }
      {
        model = "authentik_core.application";
        identifiers.slug = "firefly";
        attrs = {
          name = "Firefly III";
          provider = { model = "authentik_providers_oauth2.oauth2provider"; identifiers.name = "Firefly III"; };
          launch_url = "https://firefly.lan.valgrindr.net";
        };
      }
    ];
  };

in {
  # Render cada blueprint a un fichero YAML en /var/lib/authentik/blueprints
  # vía tmpfiles + symlink al store.
  systemd.tmpfiles.rules = lib.mapAttrsToList (name: bp:
    "L+ /var/lib/authentik/blueprints/${name}.yaml - - - - ${yamlFormat.generate "${name}.yaml" bp}"
  ) blueprints;
}
```

**Ventajas**:
- Cada nueva app que quiera OIDC = un nuevo atributo en `blueprints`. `nixos-rebuild switch` lo aplica.
- Diff-able en PR: ves exactamente qué cambia.
- Rollback gratis (revert + switch).

**Limitaciones de los blueprints**:
- No todos los modelos están soportados; algunos requieren la API a posteriori. Caso típico: el `client_secret` del provider OIDC. Solución: blueprint marca el provider con `client_secret = !env AUTHENTIK_OIDC_FIREFLY_SECRET`, valor inyectado vía sops template en el environment del container.
- API tokens: blueprints no los crean directamente; se gestionan vía `AUTHENTIK_BOOTSTRAP_TOKEN` (uno admin) o se generan a posteriori si hace falta.

---

## Fase 6 — Integración por aplicación (incremental)

Iterar por servicio, en orden de menor riesgo:

| App | Tipo | Mecanismo | Esfuerzo |
|-----|------|-----------|----------|
| **Homepage** | UI estático | `forward_auth` sin OIDC (homepage no soporta OIDC) | 1 línea Caddy |
| **AdGuard webui** | UI sin OIDC | `forward_auth` solo (AdGuard sigue pidiendo su login si quieres doble) | 1 línea Caddy |
| **Headplane** | UI sin OIDC | `forward_auth` solo | 1 línea Caddy |
| **Firefly III** | OIDC nativo (vía `LOGIN_PROVIDER=eloquent` → OAuth) | Blueprint + env `FIREFLY_*_OAUTH_*` | medio |
| **Ghostfolio** | OIDC opcional vía plugin | Blueprint + config Ghostfolio | medio |
| **Home Assistant** | OAuth2 via `command_line` o auth_oidc HACS | Custom integration, no nativo | alto |
| **Immich** | OIDC nativo, excelente | Blueprint + Immich admin UI | bajo |
| **Jellyfin** | Plugin `jellyfin-plugin-sso` | Plugin install + blueprint | medio |
| **Seerr** | OIDC nativo desde 2.0 | Blueprint + Seerr admin | bajo |
| **Sonarr/Radarr/Prowlarr** | No tienen OIDC | `forward_auth` para UI; excluir `/api/*` paths | bajo (con exclude) |
| **qBittorrent** | No tiene OIDC | `forward_auth` para UI | bajo |
| **Recyclarr** | No tiene UI | N/A | — |

Para los que **no tienen OIDC**, `forward_auth` Caddy es suficiente: una vez logueado en Authentik no se pide credencial al servicio. El servicio sigue teniendo su login interno pero, dado que `forward_auth` ya impuso identidad, podemos:
- Configurar el servicio con bypass de auth a la subnet (lo que ya hacemos para *arrs).
- O dejar la doble auth (segura, ligeramente molesta).

Para Immich/Jellyfin/Seerr (OIDC nativo) el usuario hace login UNA vez en Authentik y los apps lo reconocen automáticamente.

---

## Fase 7 — Bypass de LAN durante rollout

Para no romper nada vivo mientras se itera, configurar Authentik con un **flow** que evite forzar login a IPs LAN (192.168.1.0/24 + tailnet 100.64.0.0/10). Authentik soporta esto vía `policy_engine` en el flow: añadir una expression policy `request.context['client_ip'] in trusted_ranges`. Si match → skip auth, retorna 200.

Alternativa más simple: en Caddy, no aplicar `import authentik_auth` en handles concretos durante el rollout. Ir activándolo servicio a servicio cuando confirmes que el OIDC interno funciona.

---

## Validación end-to-end

Por cada fase, una validación concreta:

1. **Fase 1-2**: `https://auth.lan.valgrindr.net` carga login. `akadmin` + password sops → entra al admin UI. `journalctl -u podman-authentik-server -b` sin errores.
2. **Fase 3-4**: `curl -I https://homepage.lan.valgrindr.net` sin cookie debería devolver 302 a `auth.lan...` (proxy redirige al login). Tras login, request al mismo URL devuelve 200.
3. **Fase 5**: blueprint nuevo → restart container → ver el objeto en Authentik admin UI (Applications/Providers/Flows).
4. **Fase 6 (por app)**: cliente recién logueado en Authentik abre la app → sin volver a pedir credencial (si OIDC) o sin volver a pedir login Authentik (si solo `forward_auth`).

---

## Recovery cheats

- **Authentik no arranca, blueprints lo bloquean**: monta blueprints como vacío temporalmente (`extraOptions = ["-v" "/tmp/empty:/blueprints/local:ro"]`), arranca, revisa logs, corrige.
- **Olvidé la password de `akadmin`**: rota `authentik/bootstrap-password` en sops, `restartUnits` lo reaplica. El bootstrap se re-ejecuta on-restart si el user no existe (si existe, hay que entrar al worker con `ak shell` y resetear manualmente — documentar el oneliner cuando se valide).
- **`forward_auth` bloquea un endpoint API que era internal**: comprobar matcher `path /api/*` exclusion en el handle. Sonarr/Radarr/Prowlarr son los sospechosos #1.
- **Token de Prowlarr/Sonarr/Radarr deja de funcionar al activar Authentik**: confirmar que los handles de bifrost para esas APIs NO tienen `import authentik_auth`, o que el matcher path los excluye. La regla: `X-Api-Key` ≠ login humano, nunca lo metas detrás de forward_auth.
- **Postgres se queja de "role authentik does not exist"**: el `ensureUsers` se aplica en el activation; revisa `journalctl -u postgresql-setup` o reinicia postgres antes de los containers.

---

## Commit plan sugerido

Una cadena de commits aislados para que el rollback sea trivial:

```
feat(asgard): scaffold authentik container module
feat(asgard): wire authentik postgres + redis + sops bootstrap
feat(bifrost): expose auth.lan.valgrindr.net + homepage tile
feat(bifrost): caddy authentik_auth snippet
feat(asgard): authentik blueprints — default flow + admin
feat(<service>): integrate <service> with authentik via OIDC
...
```

Cada commit reanudable, validable independientemente. Mismo patrón que el media stack.
