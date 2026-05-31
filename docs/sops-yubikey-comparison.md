# SSH + sops + YubiKey: comparativa de enfoques

Comparativa objetiva de tres formas de mezclar autenticación SSH,
gestión de secretos con sops-nix y un YubiKey en una configuración
NixOS. Su objetivo es apoyar una decisión, no defender una previa.

Documentos hermanos:

- [`docs/ssh-sops-architecture.md`](./ssh-sops-architecture.md) describe
  la mecánica del setup actual.
- [`docs/yubikey-implementation-plan.md`](./yubikey-implementation-plan.md)
  es el plan ejecutivo de uno de los enfoques (Misterio77); referencia,
  no prescripción de este documento.

## 1. Resumen

Comparamos tres enfoques:

1. **emergent-minds** ([github.com/EmergentMind/nix-config](https://github.com/EmergentMind/nix-config))
   — defensa en profundidad. YubiKey como segundo factor en múltiples
   capas: PAM/U2F para sudo y login, FIDO2-LUKS, SSH `ed25519-sk`, GPG
   para firmar y descifrar, `age-plugin-yubikey` opcional. Más vectores
   asegurados, más superficie de configuración.

2. **Misterio77** ([github.com/Misterio77/nix-config](https://github.com/Misterio77/nix-config))
   — identidad OpenPGP única en YubiKey usada para SSH (vía
   `gpg-agent`), firma de commits, descifrado de sops (recipient PGP) y
   gestor de contraseñas (`pass`). Sin PAM/U2F, sin FIDO2-LUKS, sin
   `age-plugin-yubikey`.

3. **Setup actual del repo** — sops-nix activo con un age recipient
   `&sanfe` derivado de `~/.ssh/id_ed25519`, recipients de host
   derivados de cada SSH host key y bootstrap automático de la age key
   de usuario en workstations. Sin YubiKey. Es un punto de partida
   funcional, no necesariamente un destino.

Las secciones [§4](#4-enfoque-emergent-minds), [§5](#5-enfoque-misterio77)
y [§6](#6-evolucionar-el-setup-actual-sin-yubikey-baseline) describen
cada enfoque por sus propios méritos. [§7](#7-en-qué-escenarios-encaja-cada-enfoque)
mapea perfiles de usuario a enfoques; [§8](#8-trade-offs-comparados)
agrega los trade-offs en una tabla común. **No hay sección
"recomendación"**.

## 2. Tabla comparativa rápida

| Dimensión | emergent-minds | Misterio77 | Setup actual |
|---|---|---|---|
| SSH key store | YubiKey FIDO2 (`ed25519-sk`) y/o GPG-auth subkey | GPG-auth subkey en YubiKey (vía `gpg-agent --enable-ssh-support`) | `~/.ssh/id_ed25519` en disco (LUKS) |
| sops recipient de usuario | PGP (con YubiKey) y opcionalmente age | PGP (YubiKey) | age derivado de SSH user key |
| sops recipient de host | age derivado de SSH host key | age derivado de SSH host key | age derivado de SSH host key |
| Sudo | PAM/U2F (toque YubiKey) | Passphrase | Passphrase |
| Login | PAM/U2F opcional | Passphrase | Passphrase |
| LUKS | FIDO2-LUKS opcional | Passphrase | Passphrase |
| Firma de commits | GPG en YubiKey | GPG en YubiKey | OpenPGP configurado, sin clave |
| Gestor de contraseñas | No documentado explícitamente | `pass` cifrado con la misma PGP de YubiKey | No hay |
| Applets YubiKey requeridos | FIDO2 + PIV + OpenPGP | OpenPGP | Ninguno |
| Dependencias runtime extra | `pcscd`, `pam_u2f`, `fido2luks`, udev rules | `pcscd`, `scdaemon`, `gpg-agent` | — |
| Recuperación si pierdo todas las YubiKeys | Backup por vector (FIDO2 fallback, U2F recovery token, GPG `$GNUPGHOME` backup) | Restaurar `$GNUPGHOME` cifrado y flashear YubiKey nueva | N/A |
| Cantidad de ficheros nix tocados respecto al setup actual | Alta (módulo YubiKey + per-host secrets + PAM + LUKS + ssh) | Media (gpg.nix + ssh.nix + git.nix + pass.nix + `.sops.yaml`) | Cero |
| Diff en `.sops.yaml` | `age:` usuario → `pgp:` + posibles secretos por dispositivo | `age:` usuario → `pgp:` | — |
| Funciona en hosts sin YubiKey física | Solo si los módulos están bien gated por host | Sí (asgard usa age del host) | Sí |

## 3. Setup actual del repo

Estado real verificable en el árbol Git al momento de escribir esto.

### Flake input

`flake.nix:17-20` — `sops-nix` está **activo** apuntando a
`github:mic92/sops-nix` con `inputs.nixpkgs.follows = "nixpkgs"`. (Nota:
`docs/yubikey-implementation-plan.md:48` aún dice "sops-nix comentado";
esa referencia quedó stale.)

### `.sops.yaml`

`.sops.yaml:1-19` declara dos anclas (`&users`, `&hosts`) y dos
`creation_rules`:

```yaml
keys:
  - &users
    - &sanfe   age1dzpr70k…   # derivado de ~/.ssh/id_ed25519
  - &hosts
    - &asgard  age1z2v0a…     # derivado del SSH host key de asgard
    - &midgard age1nryru…     # derivado del SSH host key de midgard
creation_rules:
  - path_regex: hosts/common/secrets\.ya?ml$
    key_groups: [{ age: [*sanfe, *asgard, *midgard] }]
  - path_regex: hosts/asgard/secrets\.ya?ml$
    key_groups: [{ age: [*sanfe, *asgard] }]
```

Todo `age:`. No hay aún ningún `pgp:`.

### Módulo sops-nix de NixOS

`hosts/common/core/sops.nix:1-55`:

- `sops.age.sshKeyPaths` (`sops.nix:35`) mapea cada SSH host key
  ed25519 (`config.services.openssh.hostKeys`) a su path. sops-nix
  deriva el age recipient del host al descifrar.
- `defaultSopsFile` (`sops.nix:31-34`) selecciona
  `hosts/<host>/secrets.yaml` si existe, si no
  `hosts/common/secrets.yaml`.
- Bootstrap automático de la age key de usuario (`sops.nix:37-45`):
  cuando `hostSpec.profile == "workstation"` (`workstation.nix:9`) y la
  cadena `user-age-keys` aparece en `hosts/common/secrets.yaml`, se
  declara un secreto `user-age-keys/${username}` con `path` a
  `~/.config/sops/age/keys.txt`, con `owner = username`, `mode = 0400`.
  Primera workstation aprovisionada: el host descifra con su SSH host
  key, materializa la age key del usuario en disco, y el usuario usa
  `sops` sin tocar `ssh-to-age` manualmente.
- Script de activación (`sops.nix:51-54`) que arregla ownership de
  `~/.config`.

### Configuración de usuario

- `home/sanfe/common/core/default.nix:30` — `programs.gpg.enable = true`
  sin clave (no hay `programs.gpg.publicKeys`, no hay identidad GPG en
  disco).
- `home/sanfe/common/core/default.nix:31-40` — git con `userName = "sanfeps"`,
  `userEmail = "sanfelixguajardo@gmail.com"`, `signing.format = "openpgp"`
  pero `signByDefault = false` y sin `key`. Slot listo, sin inquilino.
- `home/sanfe/common/core/default.nix:42-46` — `services.gpg-agent` con
  `pinentry-curses` y **sin** `enableSshSupport`.
- `home/sanfe/features/cli/ssh.nix:9-28` — bloque `net` con
  `identityFile = "~/.ssh/lykill"` e `identitiesOnly = true`. Marcado en
  memoria como transitorio pre-YubiKey.

### Persistencia

`home/sanfe/common/core/default.nix:71-73` ya persiste `.ssh`, `.pki`,
`.config/sops`. No persiste `.gnupg` (irrelevante mientras no haya GPG
activo).

## 4. Enfoque emergent-minds

### Qué hace

emergent-minds usa el YubiKey como factor adicional en múltiples
vectores de autenticación:

- **PAM/U2F para login y sudo** (`modules/hosts/common/yubikey.nix`),
  vía `pam_u2f` + `yubikey-manager` + `yubioath-flutter`.
- **`pcscd`** habilitado, reglas udev para enlazar/desenlazar SSH keys
  al insertar/extraer el dispositivo.
- **Auto screen lock/unlock** opcional al insertar/extraer YubiKey.
- **SSH keys identificadas por dispositivo** (`hosts/common/optional/yubikey.nix`
  define un map `identifiers = { mara = 14574244; maya = 12549033; … };`),
  con secretos sops por dispositivo (`~/.ssh/id_maya`, `id_mara`,
  `id_manu` y `~/.config/Yubico/u2f_keys`, ver
  `home/common/optional/sops.nix`). El patrón sugiere claves `*-sk`
  (FIDO2 resident) o claves separadas por YubiKey física.
- **FIDO2-LUKS** mencionado en el README como capacidad
  ("touch-based decryption during LUKS2 decryption").
- **GPG** para firma de commits y SSH-auth tradicional (el módulo de
  git en `home/common/core/git.nix` no incluye signing inline; el README
  lo lista como capacidad del YubiKey).
- **Secretos vía sops-nix** con un repo privado externo (`nix-secrets`)
  pulled como flake input. La age key del usuario va a
  `~/.config/sops/age/keys.txt`. `home/common/optional/sops.nix` incluye
  un FIXME explícito sobre refactorizar las opciones de YubiKey en un
  módulo dedicado para evitar interferencia de bootstrapping.

### Características

- Cobertura amplia: cada vector de autenticación tiene refuerzo
  hardware (sudo, login, disco, SSH, GPG).
- Identificación por dispositivo: cada YubiKey tiene su propio
  identifier en el repo; revocaciones granulares posibles.
- Configuración fragmentada en varios módulos (`modules/hosts/common/yubikey.nix`,
  `hosts/common/optional/yubikey.nix`, `home/common/optional/sops.nix`),
  todos opcionales/gated.
- Múltiples applets de YubiKey activos simultáneamente: FIDO2 + PIV +
  OpenPGP. Requiere YubiKey 5 (las Security Key no tienen OpenPGP).
- Dependencia operativa de `pam_u2f`, `pcscd`, `scdaemon`,
  `fido2-luks` y reglas udev específicas.
- Documentación dispersa entre el repo, artículo externo en
  `unmovedcentre.com`, repo `nix-secrets-reference` y vídeos.
- Recuperación distribuida: cada vector necesita su propio backup
  (passphrase de fallback FIDO2-LUKS, token recovery U2F, backup GPG).

### Implicaciones

- Un atacante con passphrase de sudo no puede escalar sin token físico.
- Disco robado sin YubiKey requiere romper el fallback (que sí existe;
  FIDO2-LUKS no elimina la passphrase, la complementa).
- Cualquier upgrade de NixOS que toque PAM, udev o el stack de
  smartcards puede romper login. Mitigable con `nixos-rebuild test`
  antes de switch, pero es vigilancia continua.
- Servidores remotos sin YubiKey física: los módulos relevantes
  (`yubikey.enable`, `fido2luks.enable`) deben estar gated por host.
  Equivalente a "feature flag por máquina".

## 5. Enfoque Misterio77

### Qué hace

Una **identidad OpenPGP** única (clave maestra Certify-only + subkeys
S/E/A) cargada en YubiKey vía applet OpenPGP. Esa identidad sirve para
todo:

- **SSH** vía `gpg-agent` con `enableSshSupport = true` y la subkey [A]
  expuesta como `SSH_AUTH_SOCK` (`home/gabriel/features/cli/gpg.nix`
  con el keygrip de Authentication, ej.
  `149F16412997785363112F3DBD713BC91D51B831`).
- **Firma de commits** con la subkey [S]
  (`home/gabriel/features/cli/git.nix`: `signing.format = "openpgp"`,
  `signing.key = "CE707A2C…"`, `commit.gpgSign = true`,
  `gpg.program = gpg2`).
- **Descifrado de sops** vía recipient PGP (`.sops.yaml` declara
  `&misterio 7088C7421873E0DB97FF17C2245CAB70B4C225E9` como recipient
  PGP; cada host como recipient age derivado de su SSH host key).
- **`pass`** cifrado con la misma PGP key
  (`home/gabriel/features/pass/default.nix`):

  ```nix
  programs.password-store = {
    enable = true;
    settings.PASSWORD_STORE_DIR = "$HOME/.password-store";
    package = pkgs.pass.withExtensions (p: [p.pass-otp]);
  };
  home.persistence."/persist".directories = [".password-store"];
  ```

- **Agent forwarding** sobre SSH para usar el YubiKey local en hosts
  remotos: `ssh.nix` define `remoteForwards` que reexpone
  `S.gpg-agent.extra` del cliente como `S.gpg-agent` en el servidor
  (más un servicio systemd `link-gnupg-sockets` que symlinkea
  `/run/user/$UID/gnupg` a `~/.gnupg-sockets`).
- **pinentry** condicional según sesión (gnome3 si GTK,
  curses/tty si no).
- Trust model `tofu+pgp`, `pgp.asc` importado desde el repo con
  `trust = 5`.

### Características

- Una sola identidad criptográfica; un solo modelo mental.
- Backup centralizado: un `$GNUPGHOME.tar.gz.gpg` cifrado con
  passphrase. Pierdes las dos YubiKeys → restauras GNUPGHOME, flasheas
  YubiKeys nuevas con las mismas subkeys, todo sigue funcionando sin
  re-cifrar nada ni tocar GitHub.
- Diff respecto al setup actual del repo: cambiar `age:` del usuario
  por `pgp:` en `.sops.yaml`, añadir `pgp.asc`, tres ficheros nix
  nuevos (`gpg.nix`, `git.nix`, `pass.nix`) y persistir `.gnupg`.
- Dependencias runtime acotadas: `scdaemon` + `gpg-agent` + un
  pinentry.
- Sudo, login y LUKS siguen siendo passphrase: el YubiKey no participa
  en esos vectores.
- Solo aplica el applet OpenPGP de la YubiKey. Funciona en YubiKey 5
  (las Security Key 2 no tienen OpenPGP). FIDO2 y PIV quedan
  disponibles pero no usados.
- Multi-YubiKey: las dos llaves contienen las mismas subkeys
  (`keytocard` desde el mismo `$GNUPGHOME`); SSH y sops ven cualquiera
  como la misma identidad.

### Implicaciones

- Un atacante con passphrase de sudo escala con esa passphrase sola.
- Disco robado: solo passphrase LUKS protege; sin segundo factor.
- `gpg-agent` puede ser quisquilloso con el env de sesión gráfica
  (clásico `updatestartuptty` al cambiar de tty). Hay troubleshooting
  documentado.
- Servidor sin YubiKey local: se accede vía agent forwarding; el
  módulo lo soporta.
- Si pierdes las dos YubiKeys **y** el backup `$GNUPGHOME`, la
  identidad se pierde definitivamente. (Cierto de cualquier esquema
  basado en una única identidad criptográfica.)

## 6. Evolucionar el setup actual sin YubiKey (baseline)

No introducir YubiKey también es una opción legítima. El setup actual
ya cubre:

- Cifrado de secretos por host con sops-nix (host descifra sin
  intervención).
- Identidad de usuario para sops vía age key derivada del SSH key.
- Bootstrap automático de la age key del usuario en workstations
  nuevas (no hace falta `ssh-to-age` manual).
- SSH key personal en disco bajo LUKS.

Mejoras incrementales sin saltar a YubiKey:

- **Aislar `user-age-keys/<user>`** en un fichero separado cifrado solo
  a workstations (`hosts/common/workstation-secrets.yaml`) para que el
  servidor no pueda extraer la age key del usuario. Mencionado en
  `docs/ssh-sops-architecture.md:140-146`.
- **Firma de commits con SSH key** (`gpg.format = "ssh"`,
  `signing.key = ~/.ssh/id_ed25519`). Git la soporta nativamente desde
  2.34. Cero infraestructura GPG.
- **`age-plugin-yubikey`** como paso intermedio: la age key del usuario
  vive en el slot PIV de la YubiKey, sin necesidad de stack GPG. Más
  ligero que Misterio77 pero solo cubre sops; no aporta SSH ni firma.
- **Mover la passphrase de SSH key** de "ninguna" a "fuerte" si todavía
  no la tiene, como medida intermedia barata.

Esta vía no es excluyente con migrar luego: un setup mejorado-pero-sin-YubiKey
sigue siendo punto de partida válido para Misterio77 o emergent-minds más
adelante.

## 7. En qué escenarios encaja cada enfoque

Sin recomendación; mapeo objetivo de prioridades a opciones:

### Si la prioridad es resistencia ante acceso físico a la máquina

- **emergent-minds** lo cubre directamente (FIDO2-LUKS + PAM/U2F en
  sudo y login). Atacante con la máquina robada y desbloqueada no puede
  escalar sin token físico.
- **Misterio77** no cubre ese vector: pasa por la passphrase de sudo y
  por la passphrase de LUKS.
- **Setup actual** tampoco lo cubre.

### Si la prioridad es resistencia ante extracción de la age key del usuario

- **emergent-minds** y **Misterio77** la cubren igual: la clave nunca
  sale del YubiKey, no es exportable, requiere toque para usar.
- **Setup actual** la deja extraíble por cualquier host con permisos
  sobre `hosts/common/secrets.yaml` (hoy: asgard). Mitigable aislando el
  bootstrap a workstation-secrets.

### Si la prioridad es minimizar superficie de fallo / mantenimiento

- **Setup actual** > **Misterio77** > **emergent-minds** (en ese
  orden de superficie creciente).
- Un upgrade roto en `pam_u2f` o en el stack scdaemon afecta más en
  emergent-minds que en Misterio77, y nada en el setup actual.

### Si la prioridad es identidad unificada (SSH + sign + sops + pass)

- **Misterio77** está diseñado exactamente para eso. Una clave, un
  toque, todos los vectores cubiertos.
- **emergent-minds** llega ahí pero por dos caminos (FIDO2 para
  SSH/sudo, GPG para firma/sops). Coexistencia válida pero más
  decisiones operativas.
- **Setup actual** no la ofrece.

### Si la prioridad es trabajar con servidores remotos sin YubiKey

- **Misterio77** lo resuelve con agent forwarding sobre SSH
  (`remoteForwards` en `ssh.nix`).
- **emergent-minds** funciona si los módulos YubiKey están gated por
  host correctamente; el énfasis del repo está en workstations.
- **Setup actual** no requiere nada especial (asgard descifra con su
  propia SSH host key).

### Si la prioridad es coste de cambio respecto al estado actual

- **Setup actual**: cero.
- **Misterio77**: rotar `age: &sanfe` → `pgp:` en `.sops.yaml`, añadir
  `pgp.asc`, 3-4 ficheros nix nuevos, persistir `.gnupg`. Más Fase 1
  manual offline (~1h enrolando YubiKeys).
- **emergent-minds**: lo anterior más módulo `yubikey.nix`, opciones
  PAM, opcionalmente FIDO2-LUKS (que requiere re-enrollment de slot
  LUKS), secretos sops adicionales por dispositivo. Estimación
  difícilmente menor a un fin de semana.

### Si la prioridad es defensa en profundidad sin compromiso

- **emergent-minds** es el enfoque que apunta ahí explícitamente.
- **Misterio77** acepta conscientemente dejar sudo/login/LUKS en
  passphrase como decisión de robustez (PAM frágil).
- **Setup actual** está en el extremo opuesto del eje
  defensa-en-profundidad.

## 8. Trade-offs comparados

| Vector | emergent-minds | Misterio77 | Setup actual |
|---|---|---|---|
| Sudo si comprometen la passphrase | Bloqueado por toque | Comprometido | Comprometido |
| Login local si comprometen passphrase | Bloqueado por toque | Comprometido | Comprometido |
| Disco robado, sin LUKS abierto | Passphrase LUKS o FIDO2 (lo que esté config) | Passphrase LUKS | Passphrase LUKS |
| Extracción de age/PGP key del usuario | Imposible (en YubiKey) | Imposible (en YubiKey) | Posible si comprometen un host con permisos |
| SSH key personal exportable | No (en YubiKey) | No (en YubiKey) | Sí (en disco bajo LUKS) |
| Recuperación tras perder ambas YubiKeys | Backup por vector | Restaurar `$GNUPGHOME` | N/A |
| Riesgo de bricked sistema por config rota | Alto (PAM/udev/LUKS) | Bajo (solo `gpg-agent`) | Mínimo |
| Coste de implementación inicial | Alto | Medio | Cero |
| Coste de mantenimiento por upgrade NixOS | Vigilancia activa de PAM/scdaemon/fido2 | Vigilancia ligera de scdaemon/gpg-agent | Ninguno extra |
| Trabajar sin YubiKey en una emergencia | Requiere fallbacks pre-configurados por vector | Solo afecta SSH/sops/sign; sudo y disco siguen funcionando | N/A |

## 9. Notas sobre el plan ejecutivo existente

`docs/yubikey-implementation-plan.md` describe en detalle cómo
implementar el enfoque Misterio77 sobre este repo (Fases 1-8, ~4-6h).
Si la decisión final es **otro enfoque**, ese plan queda inválido en
gran parte:

- **Si se elige emergent-minds:** la Fase 1 (enrollment OpenPGP) sigue
  siendo necesaria para la parte GPG, pero hay que añadir enrollment
  FIDO2 + PIV, módulo `yubikey.nix` por host, configuración PAM,
  opcional FIDO2-LUKS (que requiere reformatear o re-enroll slot LUKS).
- **Si se elige evolucionar el setup actual:** todo el plan queda
  archivado; las mejoras incrementales mencionadas en §6 no requieren
  ese plan.

El plan no se borra automáticamente — sigue siendo referencia útil si
se vuelve a considerar Misterio77 más adelante.

## 10. Referencias

- [emergent-minds nix-config — modules/hosts/common/yubikey.nix](https://github.com/EmergentMind/nix-config/blob/dev/modules/hosts/common/yubikey.nix)
- [emergent-minds nix-config — hosts/common/optional/yubikey.nix](https://github.com/EmergentMind/nix-config/blob/dev/hosts/common/optional/yubikey.nix)
- [emergent-minds nix-config — hosts/common/core/sops.nix](https://github.com/EmergentMind/nix-config/blob/dev/hosts/common/core/sops.nix)
- [emergent-minds nix-config — home/common/optional/sops.nix](https://github.com/EmergentMind/nix-config/blob/dev/home/common/optional/sops.nix)
- [Misterio77 nix-config — .sops.yaml](https://github.com/Misterio77/nix-config/blob/main/.sops.yaml)
- [Misterio77 nix-config — home/gabriel/features/cli/gpg.nix](https://github.com/Misterio77/nix-config/blob/main/home/gabriel/features/cli/gpg.nix)
- [Misterio77 nix-config — home/gabriel/features/cli/ssh.nix](https://github.com/Misterio77/nix-config/blob/main/home/gabriel/features/cli/ssh.nix)
- [Misterio77 nix-config — home/gabriel/features/cli/git.nix](https://github.com/Misterio77/nix-config/blob/main/home/gabriel/features/cli/git.nix)
- [Misterio77 nix-config — home/gabriel/features/pass/default.nix](https://github.com/Misterio77/nix-config/blob/main/home/gabriel/features/pass/default.nix)
- [drduh/YubiKey-Guide](https://github.com/drduh/YubiKey-Guide)
- [Mic92/sops-nix](https://github.com/Mic92/sops-nix)
- [`age-plugin-yubikey`](https://github.com/str4d/age-plugin-yubikey)
- Documento local: [`docs/ssh-sops-architecture.md`](./ssh-sops-architecture.md)
- Documento local: [`docs/yubikey-implementation-plan.md`](./yubikey-implementation-plan.md)
