# Plan de implementación YubiKey + GPG + sops-nix (estilo Misterio77)

> **Objetivo:** una identidad OpenPGP única alojada en YubiKey que sirva para SSH, firma de commits, descifrado de sops y `pass`. Sin `pam_u2f` para sudo. Sin LUKS-FIDO2. Implementación pura del enfoque Misterio77, adaptada a este repo.
>
> **No incluye** (decisiones tomadas conscientemente): toque para sudo, toque para LUKS, `age-plugin-yubikey`, `ssh-keygen -t ed25519-sk`, smartcard FIDO2.

---

## Índice

1. [Pre-requisitos hardware y decisiones](#0-pre-requisitos)
2. [Fase 1 — Enrolar las YubiKeys (manual, fuera de NixOS)](#fase-1--enrolar-las-yubikeys)
3. [Fase 2 — Configurar GPG en home-manager](#fase-2--configurar-gpg-en-home-manager)
4. [Fase 3 — SSH vía gpg-agent](#fase-3--ssh-vía-gpg-agent)
5. [Fase 4 — Firma de commits con la YubiKey](#fase-4--firma-de-commits-con-la-yubikey)
6. [Fase 5 — sops-nix con PGP recipient](#fase-5--sops-nix-con-pgp-recipient)
7. [Fase 6 — `pass` (gestor de contraseñas)](#fase-6--pass-gestor-de-contraseñas)
8. [Fase 7 — Persistencia (impermanence)](#fase-7--persistencia)
9. [Fase 8 — Validación end-to-end](#fase-8--validación-end-to-end)
10. [Backup y contingencias](#backup-y-contingencias)
11. [Apéndice A — Comandos de troubleshooting GPG](#apéndice-a--troubleshooting-gpg)
12. [Apéndice B — Adaptación por host](#apéndice-b--adaptación-por-host)

---

## 0. Pre-requisitos

### Hardware

- **2× YubiKey 5** (modelos 5 NFC, 5C NFC o 5C). NO Security Key 2 — necesitamos la applet OpenPGP que esos no tienen.
- Una USB-A o USB-C según el modelo.
- (Opcional pero recomendado) un USB live o máquina aislada para generar la clave maestra offline.

### Decisiones tomadas en esta versión del plan

| Decisión | Elección | Razón |
|---|---|---|
| ¿Generar la clave maestra offline o on-card? | **Offline** (en una shell efímera, exportar backups cifrados) | Permite mantener subkeys con expiración renovable y cargar las mismas subkeys en las dos YubiKeys |
| Algoritmo | **ed25519 / cv25519** (no RSA-4096) | Más rápido, soportado por todas las YubiKeys 5, criptografía moderna |
| Touch policy de las subkeys | **`on`** para Sign y Auth, **`cached`** para Encrypt | `on` evita firmas en background; `cached` (~15s) hace `pass` y sops usables sin tocar 6 veces seguidas |
| Compositor para pinentry | **`pinentry-gnome3`** en midgard/raidho (Wayland + dconf), `pinentry-tty` en asgard | midgard tiene `programs.dconf.enable = true`, GNOME pinentry funciona bien |
| Hosts donde activar GPG | **midgard, raidho** | asgard es servidor remoto, no ve la llave físicamente |
| Hosts donde activar sops | **midgard, raidho, asgard** (los tres) | asgard recibe secretos cifrados a su clave de host |

### Estado actual del repo (referencia)

- `flake.nix:17-20` — input `sops-nix` comentado
- `hosts/common/core/sops.nix` — todo el contenido comentado
- `home/sanfe/common/core/default.nix:30` — `programs.gpg.enable = true` ya está, pero sin claves
- `home/sanfe/common/core/default.nix:33-37` — `programs.git.signing.format = "openpgp"` con `signByDefault = false`, sin `key`
- `home/sanfe/common/core/default.nix:40-44` — `services.gpg-agent` con `pinentry-curses` y sin `enableSshSupport`
- `hosts/common/secrets.yaml` — ya cifrado a `age1kpyzk29547qtzsrq…` (clave del host antiguo)
- Persistencia en `home/sanfe/common/core/default.nix:55-123` — incluye `.ssh` y `.pki`, **falta** `.gnupg`

---

## Fase 1 — Enrolar las YubiKeys

> **Esta fase es manual y se hace UNA vez. NixOS no entra todavía.** Sigue [drduh/YubiKey-Guide](https://github.com/drduh/YubiKey-Guide) si tienes dudas — abajo está el resumen mínimo.

### 1.1. Preparar entorno aislado

```bash
nix shell nixpkgs#gnupg nixpkgs#yubikey-manager nixpkgs#cryptsetup

# Trabajamos en RAM para que no quede rastro en disco
export GNUPGHOME=$(mktemp -d -t gnupg_$(date +%Y%m%d%H%M)_XXX)
cd $GNUPGHOME

# Config endurecida
cat > gpg.conf <<EOF
personal-cipher-preferences AES256 AES192 AES
personal-digest-preferences SHA512 SHA384 SHA256
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
charset utf-8
no-comments
no-emit-version
no-greeting
keyid-format 0xlong
list-options show-uid-validity
verify-options show-uid-validity
with-fingerprint
require-cross-certification
no-symkey-cache
use-agent
throw-keyids
EOF
```

### 1.2. Generar la clave maestra (Certify-only)

```bash
# Genera passphrase fuerte y guárdala en sitio seguro temporalmente
PASS=$(gpg --gen-random --armor 0 24)
echo "PASSPHRASE TEMPORAL: $PASS"   # ← anótala en papel, la usaremos varias veces

gpg --batch --passphrase "$PASS" --quick-generate-key \
  "Javier San Felix <javsanfelix@gmail.com>" ed25519 cert never

# Captura la fingerprint (la necesitarás en TODOS los archivos nix)
KEYFP=$(gpg --list-options show-only-fpr-mbox -k | awk '{print $1; exit}')
echo "FINGERPRINT MAESTRA: $KEYFP"
```

> 📋 **Anota la `KEYFP`**, la usarás en `programs.git.signing.key`, `services.gpg-agent.sshKeys`, y `.sops.yaml`.

### 1.3. Generar las 3 subkeys (S/E/A)

```bash
gpg --batch --pinentry-mode=loopback --passphrase "$PASS" \
  --quick-add-key "$KEYFP" ed25519 sign 2y
gpg --batch --pinentry-mode=loopback --passphrase "$PASS" \
  --quick-add-key "$KEYFP" cv25519 encr 2y
gpg --batch --pinentry-mode=loopback --passphrase "$PASS" \
  --quick-add-key "$KEYFP" ed25519 auth 2y

gpg -K --with-keygrip
```

> 📋 **Anota los keygrips** de cada subkey (los necesitarás para `services.gpg-agent.sshKeys` — el de Auth — y para identificar Sign/Encrypt si quieres).

### 1.4. Backup de la clave maestra y subkeys

```bash
# Exporta TODO (maestra + subkeys + trustdb) a un .tar cifrado con passphrase
tar -czf - $GNUPGHOME | \
  gpg --symmetric --cipher-algo AES256 --output ~/yubikey-backup-$(date +%Y%m%d).tar.gz.gpg

# Copia ese .gpg a 2-3 USBs, guárdalos en sitios físicos distintos.
# Imprime también la passphrase del backup (papel, caja fuerte).
```

> ⚠️ **Sin este backup, si pierdes ambas YubiKeys no puedes regenerar nuevas subkeys.** No saltes este paso.

### 1.5. Inicializar la primera YubiKey

Inserta YubiKey #1.

```bash
# Cambia los PINs por defecto (123456 user / 12345678 admin)
ykman openpgp access change-pin             # PIN de usuario (6+ dígitos)
ykman openpgp access change-admin-pin       # Admin PIN (8+ dígitos)
ykman openpgp access change-reset-code      # Reset code

# Verifica
gpg --card-status
```

### 1.6. Mover las subkeys a la YubiKey #1

```bash
gpg --edit-key "$KEYFP"

# En el prompt gpg> :
gpg> key 1                # selecciona subkey Sign
gpg> keytocard
gpg> 1                    # slot Signature
gpg> key 1                # deselecciona
gpg> key 2                # selecciona subkey Encrypt
gpg> keytocard
gpg> 2                    # slot Encryption
gpg> key 2
gpg> key 3                # selecciona subkey Auth
gpg> keytocard
gpg> 3                    # slot Authentication
gpg> save
```

### 1.7. Configurar touch policies (YubiKey #1)

```bash
ykman openpgp keys set-touch sig on
ykman openpgp keys set-touch aut on
ykman openpgp keys set-touch enc cached
# Te pedirá el Admin PIN
```

### 1.8. Repetir 1.5–1.7 con la YubiKey #2

Importante: para la #2 **necesitas reimportar las subkeys originales** (las que están ahora en #1 son referencias-stub, no las claves reales). Por eso no borraste el `$GNUPGHOME` todavía.

```bash
# Vuelve al GNUPGHOME temporal si lo cerraste:
export GNUPGHOME=/ruta/al/gnupg_temp_anterior   # o re-extrae el backup

# Reimporta para que las subkeys reales estén disponibles otra vez
gpg --delete-secret-keys "$KEYFP"
gpg --import < (extrae el backup)
# (en la práctica: trabaja directamente desde el GNUPGHOME temporal sin haberlo borrado)
```

Ahora con YubiKey #2 insertada, repite §1.5, §1.6, §1.7.

### 1.9. Exportar la clave pública

```bash
gpg --armor --export "$KEYFP" > ~/nix-config/home/sanfe/pgp.asc
# Guárdala también en un servidor de claves si quieres, pero no es necesario
```

> 📋 Este `pgp.asc` se commitea al repo y home-manager lo importará automáticamente.

### 1.10. Limpieza del entorno temporal

**Después de verificar que ambas YubiKeys funcionan** (`gpg --card-status` con cada una insertada):

```bash
# Borra el GNUPGHOME temporal (asegúrate de tener el backup cifrado)
rm -rf $GNUPGHOME
unset PASS GNUPGHOME
```

---

## Fase 2 — Configurar GPG en home-manager

### 2.1. Eliminar la config GPG vieja

Quita las líneas de `home/sanfe/common/core/default.nix`:

```nix
# QUITAR estas líneas (ya estarán reemplazadas por el módulo nuevo):
programs.gpg.enable = true;
programs.git = {
  enable = true;
  signing = {
    format = "openpgp";
    signByDefault = false;
  };
};
services.gpg-agent = {
  enable = true;
  enableZshIntegration = true;
  pinentry.package = pkgs.pinentry-curses;
};
```

> Mantén `programs.home-manager.enable = true` y `programs.git.enable = true` (sin el bloque `signing`, lo configuraremos en su propio módulo).

### 2.2. Crear el módulo GPG

Archivo nuevo: `home/sanfe/features/cli/gpg.nix`

```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  # ⚠️ Sustituye estos por los valores reales después de Fase 1
  signingKey = "0000000000000000000000000000000000000000";  # KEYFP completa (40 hex)
  authKeygrip = "0000000000000000000000000000000000000000"; # keygrip de la subkey [A]
in {
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    sshKeys = [authKeygrip];
    enableExtraSocket = true;          # necesario para forwarding de gpg-agent por SSH
    defaultCacheTtl = 60;              # PIN cacheado 1 min después del último uso
    maxCacheTtl = 1800;                # máximo absoluto: 30 min
    defaultCacheTtlSsh = 60;
    maxCacheTtlSsh = 1800;
    pinentry.package = pkgs.pinentry-gnome3;
  };

  home.packages = with pkgs; [
    gcr      # necesario para que pinentry-gnome3 funcione
    pinentry-gnome3
  ];

  programs = let
    fixGpg = ''
      gpgconf --launch gpg-agent
    '';
  in {
    zsh.loginExtra = fixGpg;

    gpg = {
      enable = true;
      settings = {
        trust-model = "tofu+pgp";
        keyid-format = "0xlong";
        with-fingerprint = true;
      };
      publicKeys = [
        {
          source = ../../pgp.asc;
          trust = 5;                   # ultimate trust (es tu propia clave)
        }
      ];
      # Forzar disable-ccid para evitar conflicto con pcscd
      scdaemonSettings = {
        disable-ccid = true;
      };
    };
  };
}
```

### 2.3. Crear el módulo SSH (Fase 3 lo expandirá)

Archivo nuevo: `home/sanfe/features/cli/ssh.nix`

```nix
{lib, ...}: {
  programs.ssh = {
    enable = true;

    # No queremos que ssh-agent compita con gpg-agent
    addKeysToAgent = "no";

    matchBlocks = {
      # Lista tus hosts aquí; ajusta según necesites
      "github.com" = {
        identitiesOnly = true;
      };
      "midgard raidho asgard" = {
        forwardAgent = true;
        extraOptions.StreamLocalBindUnlink = "yes";
        remoteForwards = [
          {
            bind.address = "/%d/.gnupg-sockets/S.gpg-agent";
            host.address = "/%d/.gnupg-sockets/S.gpg-agent.extra";
          }
        ];
      };
    };
  };

  # Symlinkea el dir de sockets de gpg desde /run a $HOME para que ssh
  # remoteForwards pueda apuntar a una ruta estable
  systemd.user.services.link-gnupg-sockets = {
    Unit.Description = "link gnupg sockets from /run to /home";
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pkgs.coreutils \"ln\"} -Tfs /run/user/%U/gnupg %h/.gnupg-sockets";
      ExecStop = "${lib.getExe' pkgs.coreutils \"rm\"} %h/.gnupg-sockets";
      RemainAfterExit = true;
    };
    Install.WantedBy = ["default.target"];
  };
}
```

### 2.4. Cargar los módulos en `cli/default.nix`

Editar `home/sanfe/features/cli/default.nix`:

```nix
imports = [
  ./bat.nix
  ./direnv.nix
  ./fzf.nix
  ./nix-index.nix
  ./starship.nix
  ./gpg.nix      # NUEVO
  ./ssh.nix      # NUEVO
  ./zsh
];
```

### 2.5. Variante para asgard (sin GPG)

`asgard` es un servidor remoto, no debe activar gpg-agent ni pinentry-gnome3. Como `home/sanfe/asgard.nix` puede no importar `features/cli/`, verifica primero. Si lo importa, refactoriza:

- Crea `home/sanfe/features/cli/gpg.nix` (workstation only)
- Edita `cli/default.nix` para hacer condicional o muévelos a un nivel más arriba.

**Solución más simple:** dejar `cli/default.nix` sin `./gpg.nix` ni `./ssh.nix` y añadirlos explícitamente solo en `home/sanfe/midgard.nix` y `home/sanfe/raidho.nix`:

```nix
# home/sanfe/midgard.nix
imports = [
  ./common/core
  ./features/desktop/niri
  ./features/desktop/theming
  ./features/desktop/voice-assistant
  ./features/games
  ./features/cli
  ./features/cli/gpg.nix       # NUEVO — solo en workstations
  ./features/cli/ssh.nix       # NUEVO
];
```

### 2.6. Build y validación de Fase 2

```bash
cd ~/nix-config
nix fmt
nix flake check
sudo nixos-rebuild test --flake .#midgard
```

Test funcional con la YubiKey enchufada:

```bash
gpg --card-status                    # debe ver tu llave
gpg --list-secret-keys               # debe listar la clave (con stub > de subkeys)
echo "test" | gpg --clearsign        # debe pedir toque y firmar
```

> ✅ **Validación obligatoria antes de seguir a Fase 3.** Si el toque no se pide o pinentry no aparece, abre el [Apéndice A](#apéndice-a--troubleshooting-gpg).

---

## Fase 3 — SSH vía gpg-agent

Esto ya está mayormente hecho en Fase 2 (módulo `ssh.nix`). Aquí solo verificas y subes pubkeys.

### 3.1. Verificar que la subkey [A] está expuesta como SSH key

Con la YubiKey enchufada:

```bash
ssh-add -L
# Debería imprimir UNA línea ssh-ed25519 AAAA... cardno:000123456789
```

Si no aparece nada, comprueba que el keygrip en `services.gpg-agent.sshKeys` es el correcto (no la fingerprint, el **keygrip** de la subkey [A]).

### 3.2. Subir la pubkey SSH a GitHub

```bash
ssh-add -L | grep cardno > ~/yubikey-ssh.pub
gh ssh-key add ~/yubikey-ssh.pub --title "yubikey-1-auth"
# Repite con la YubiKey #2 (mismo output, sí, porque es la misma subkey)
# Solo necesitas subirla una vez.
```

> 📋 **Reemplaza tu `~/.ssh/id_*` actual en GitHub** si quieres limitar la autenticación solo al YubiKey. Yo recomiendo dejar también la antigua mientras validas que esto funciona, y borrarla en una semana.

### 3.3. Probar SSH

```bash
ssh -T git@github.com
# Debería pedir toque a la YubiKey y luego: "Hi sanfeps! You've successfully authenticated..."

# Probar agent forwarding hacia midgard mismo (tonto pero válido):
ssh midgard.local "ssh -T git@github.com"
# Debería pedir toque (en la llave que tienes enchufada en midgard local)
```

> ✅ Validación: SSH con YubiKey funciona local y por forward.

---

## Fase 4 — Firma de commits con la YubiKey

### 4.1. Crear módulo git con signing

Archivo nuevo: `home/sanfe/features/cli/git.nix`

```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  # ⚠️ Reemplaza con tu fingerprint real (mismo valor que en gpg.nix)
  signingKey = "0000000000000000000000000000000000000000";
in {
  programs.git = {
    enable = true;
    userName = "sanfeps";
    userEmail = "javsanfelix@gmail.com";
    signing = {
      format = "openpgp";
      key = signingKey;
      signByDefault = true;
    };
    extraConfig = {
      tag.gpgSign = true;
      gpg.program = "${config.programs.gpg.package}/bin/gpg2";
    };
  };
}
```

### 4.2. Importarlo

Edita `home/sanfe/features/cli/default.nix`:

```nix
imports = [
  ./bat.nix
  ./direnv.nix
  ./fzf.nix
  ./git.nix         # NUEVO
  ./nix-index.nix
  ./starship.nix
  ./zsh
];
```

(Y mueve `./gpg.nix` y `./ssh.nix` aquí si decidiste integrarlos a nivel cli/, o mantenlos en los hosts según §2.5.)

### 4.3. Subir la pubkey GPG a GitHub

```bash
gpg --armor --export "$KEYFP" | gh gpg-key add -
```

### 4.4. Validación

```bash
sudo nixos-rebuild test --flake .#midgard

cd ~/nix-config
echo "test" >> README.md
git add README.md
git commit -m "test: signing"   # debe pedir toque y firmar
git log --show-signature -1     # debe decir "Good signature from..."
git restore --staged README.md && git checkout README.md
git reset --hard HEAD~1         # deshacer el commit de prueba
```

> ✅ Validación: commit firmado y verificable.

---

## Fase 5 — sops-nix con PGP recipient

> **Importante:** antes de cambiar nada, **descifra el contenido actual** de `hosts/common/secrets.yaml` y guárdalo en seguro temporal:
>
> ```bash
> SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d hosts/common/secrets.yaml > /tmp/secrets-plain.yaml
> ```

### 5.1. Reactivar `sops-nix` en el flake

Edita `flake.nix`, descomenta:

```nix
sops-nix = {
  url = "github:mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 5.2. Reactivar el módulo de NixOS

Reescribe `hosts/common/core/sops.nix`:

```nix
{
  inputs,
  config,
  ...
}: let
  isEd25519 = k: k.type == "ed25519";
  getKeyPath = k: k.path;
  keys = builtins.filter isEd25519 config.services.openssh.hostKeys;
in {
  imports = [inputs.sops-nix.nixosModules.sops];

  sops = {
    defaultSopsFile = ../secrets.yaml;
    age = {
      sshKeyPaths = map getKeyPath keys;
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };
  };
}
```

### 5.3. Conseguir las age recipients de cada host

```bash
# Para cada host (midgard, raidho, asgard) — corre en el host:
nix shell nixpkgs#ssh-to-age -c \
  ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub

# Ejemplo de salida:
#   age14...
```

> 📋 Anota las 3 recipients age de los hosts (midgard, raidho, asgard).

### 5.4. Crear `.sops.yaml` en la raíz del repo

Archivo nuevo: `/home/sanfe/nix-config/.sops.yaml`

```yaml
keys:
  - &user_sanfe 0000000000000000000000000000000000000000   # KEYFP
  - &host_midgard age1...                                   # de §5.3
  - &host_raidho  age1...
  - &host_asgard  age1...

creation_rules:
  - path_regex: hosts/common/secrets\.ya?ml$
    key_groups:
      - pgp:
          - *user_sanfe
        age:
          - *host_midgard
          - *host_raidho
          - *host_asgard

  - path_regex: hosts/midgard/secrets\.ya?ml$
    key_groups:
      - pgp:
          - *user_sanfe
        age:
          - *host_midgard

  - path_regex: hosts/raidho/secrets\.ya?ml$
    key_groups:
      - pgp:
          - *user_sanfe
        age:
          - *host_raidho

  - path_regex: hosts/asgard/secrets\.ya?ml$
    key_groups:
      - pgp:
          - *user_sanfe
        age:
          - *host_asgard
```

### 5.5. Re-encriptar el secrets.yaml existente

```bash
cd ~/nix-config

# YubiKey enchufada — sops va a pedir toque
sops updatekeys hosts/common/secrets.yaml
# Verifica que ahora el bloque sops: incluye tanto pgp como age recipients
sops -d hosts/common/secrets.yaml | head -5
```

### 5.6. Reactivar el secret de usuario

Edita `hosts/common/users/sanfe/default.nix`, descomenta:

```nix
sops.secrets.sanfe-password = {
  sopsFile = ../../secrets.yaml;
  neededForUsers = true;
};
```

Y considera usar el password en `users.users.sanfe.hashedPasswordFile = config.sops.secrets.sanfe-password.path;` (en vez de `initialPassword = "sanfe"`).

### 5.7. Validación

```bash
sudo nixos-rebuild test --flake .#midgard
sudo cat /run/secrets/sanfe-password   # debe imprimir tu contraseña
```

Edita un secreto:

```bash
sops hosts/common/secrets.yaml         # debe pedir toque YubiKey, abrir editor con plaintext
```

> ✅ Validación: sops descifra para el host (sin toque, host age key) y para ti (con toque, PGP key en YubiKey).

---

## Fase 6 — `pass` (gestor de contraseñas)

### 6.1. Crear módulo pass

Archivo nuevo: `home/sanfe/features/cli/pass.nix`

```nix
{pkgs, ...}: {
  programs.password-store = {
    enable = true;
    settings = {
      PASSWORD_STORE_DIR = "$HOME/.password-store";
    };
    package = pkgs.pass.withExtensions (p: [p.pass-otp]);
  };
}
```

### 6.2. Importarlo

Edita `home/sanfe/features/cli/default.nix`:

```nix
imports = [
  ./bat.nix
  ./direnv.nix
  ./fzf.nix
  ./git.nix
  ./nix-index.nix
  ./pass.nix         # NUEVO
  ./starship.nix
  ./zsh
];
```

### 6.3. Inicializar el store (manual, una vez)

```bash
sudo nixos-rebuild test --flake .#midgard
pass init "$KEYFP"     # con tu fingerprint real
pass git init
pass git remote add origin git@github.com:sanfeps/password-store.git   # opcional, repo privado
```

### 6.4. Probar

```bash
pass generate test 32       # genera un password aleatorio
pass show test              # debe pedir toque y mostrarlo
pass rm test
```

> ✅ Validación: pass funciona con la YubiKey.

---

## Fase 7 — Persistencia

Edita `home/sanfe/common/core/default.nix`, en `home.persistence."/persist".directories`, **añade** estas entradas (las demás ya existen):

```nix
# GPG state
".gnupg"

# Pass store
".password-store"
```

Y en `files`, considera añadir nada más (gpg-agent regenera sus sockets en `/run/user/$UID/gnupg`, que es tmpfs y no necesita persistir).

> ⚠️ **El permiso de `.gnupg` debe ser 0700.** impermanence respeta los permisos del directorio fuente. Si después del primer reboot ves errores tipo *"unsafe permissions"*, ejecuta `chmod 700 /persist/home/sanfe/.gnupg` y reactiva.

---

## Fase 8 — Validación end-to-end

Antes de hacer `git push` (recordatorio: nunca pusheo sin validar end-to-end), ejecuta este checklist con la YubiKey enchufada:

- [ ] `gpg --card-status` muestra la llave
- [ ] `ssh-add -L` lista la subkey de Auth
- [ ] `ssh -T git@github.com` autentica con toque
- [ ] `git commit --allow-empty -m "verify"` firma con toque
- [ ] `git log --show-signature -1` dice *"Good signature"*
- [ ] `sudo cat /run/secrets/sanfe-password` funciona (host descifra)
- [ ] `sops hosts/common/secrets.yaml` abre editor con toque (tú descifras)
- [ ] `pass show test` funciona (después de crear el test)
- [ ] **Reboot y repite todos los anteriores** — confirma que la persistencia de `.gnupg` está bien

Repite el checklist con la **YubiKey #2** insertada (sin la #1) — debe funcionar todo igual, porque ambas tienen las mismas subkeys.

Una vez todo OK:

```bash
cd ~/nix-config
git add -A
git commit -m "feat(yubikey): pgp identity with sops-nix integration"
# NO hacer push hasta haber confirmado todo arriba
```

---

## Backup y contingencias

### Materiales que tienes que tener seguros (en sitios físicos distintos)

1. **Backup cifrado del GNUPGHOME inicial** (`yubikey-backup-YYYYMMDD.tar.gz.gpg`) — en 2-3 USBs/SSDs offline.
2. **Passphrase del backup** — en papel, caja fuerte / safety deposit box.
3. **PIN, Admin PIN, Reset code** de cada YubiKey — en gestor de contraseñas redundante (ej: 1Password backup, anotación cifrada con `passage`).
4. **Las dos YubiKeys físicas** — una contigo siempre, la #2 en sitio seguro distinto de tu casa.
5. **Tu pgp.asc** (clave pública) — en el repo nix-config y en `keys.openpgp.org`.

### ¿Qué hacer si pierdes UNA YubiKey?

1. Revoca solo esa YubiKey (no la clave maestra) usando un revocation cert generado en Fase 1.
2. Compra una YubiKey nueva.
3. Restaura el backup `$GNUPGHOME` y repite §1.5–§1.7 con la nueva.
4. Sube nada a GitHub porque las subkeys son las mismas.

### ¿Qué hacer si pierdes AMBAS YubiKeys?

1. Restaura el backup `$GNUPGHOME` en una máquina aislada.
2. Genera un revocation cert con la maestra y publícalo.
3. Crea subkeys nuevas, cárgalas en YubiKeys nuevas.
4. Actualiza `pgp.asc` en el repo, sube nueva pubkey a GitHub, **re-encripta sops** con la nueva fingerprint, **regenera commits firmados** si te importa la historia (no, no te importa).

### ¿Qué hacer si pierdes el backup `$GNUPGHOME`?

Game over para esta identidad. Genera una nueva clave maestra desde cero, repite todo. Por eso el backup es crítico.

---

## Apéndice A — Troubleshooting GPG

### "card not present" cuando sí está enchufada

```bash
# Recargar gpg-agent
gpgconf --kill all
gpgconf --launch gpg-agent
gpg-connect-agent "scd serialno" "learn --force" /bye
gpg --card-status
```

### pinentry no aparece (cuelga el comando)

```bash
# Ver qué pinentry está usando
gpg-connect-agent 'getinfo std_session_env DISPLAY' /bye
gpg-connect-agent 'getinfo std_session_env WAYLAND_DISPLAY' /bye

# Si está vacío, gpg-agent no heredó el env de la sesión gráfica
gpg-connect-agent updatestartuptty /bye
```

### Conflicto pcscd ↔ scdaemon

Verifica que en `gpg.nix` tienes `scdaemonSettings.disable-ccid = true;` — si lo cambiaste, repite `nixos-rebuild test`.

### SSH no encuentra ninguna llave después de reboot

```bash
gpg-connect-agent updatestartuptty /bye
gpg --card-status     # esto fuerza a gpg-agent a redetectar la llave
ssh-add -L            # debería listar la subkey ahora
```

Si persiste, comprueba que `link-gnupg-sockets.service` está activo:

```bash
systemctl --user status link-gnupg-sockets.service
ls -la ~/.gnupg-sockets    # debe ser symlink a /run/user/$UID/gnupg
```

### "decryption failed: No secret key" en sops

Comprueba que tu YubiKey está enchufada y que la fingerprint en `.sops.yaml` coincide con la de tu clave (ojo a fingerprint vs keyid corto).

```bash
gpg --list-keys --with-colons | grep ^fpr
```

### Commit no se firma

```bash
git config --get user.signingKey   # debe ser tu fingerprint
git config --get gpg.program       # debe ser path a gpg2
GIT_TRACE=1 git commit -m "test"   # ver qué pasa
```

---

## Apéndice B — Adaptación por host

| Host | GPG home-manager | sops-nix | Notas |
|---|---|---|---|
| **midgard** | ✅ Sí (workstation, dconf, Niri/Wayland → pinentry-gnome3) | ✅ Sí (host age key) | Importa `cli/gpg.nix`, `cli/ssh.nix`, `cli/git.nix`, `cli/pass.nix` |
| **raidho** | ✅ Sí (laptop, mismo setup que midgard) | ✅ Sí | Mismo import set |
| **asgard** | ❌ No (servidor remoto, no ve YubiKey) | ✅ Sí (host age key only) | NO importar `cli/gpg.nix` ni `cli/ssh.nix`. Sigue firmando commits desde tu workstation, no desde el servidor. |

Para asgard concretamente, en `home/sanfe/asgard.nix` mantén imports SIN los módulos GPG, y en `flake.nix` la entrada `homeConfigurations."sanfe@asgard"` ya está activa.

---

## Orden de ejecución resumen

1. ✅ Compras 2× YubiKey 5
2. ✅ Fase 1 manual (offline, ~1 hora) → tienes pgp.asc, fingerprints, backups
3. ✅ Fase 2 — añadir gpg.nix, validar `gpg --card-status`
4. ✅ Fase 3 — validar `ssh -T git@github.com` con toque
5. ✅ Fase 4 — validar commit firmado
6. ✅ Fase 5 — descifrar viejo secrets.yaml, reactivar sops, re-encriptar, validar
7. ✅ Fase 6 — `pass init`, validar
8. ✅ Fase 7 — añadir persistencia, reboot, validar
9. ✅ Fase 8 — checklist completo con ambas llaves
10. ✅ Commit local
11. ⛔ **NO push** hasta confirmación final tras 24h de uso real
12. ✅ Push

Tiempo total estimado: **~4-6 horas** (sin contar el tiempo de aprender los conceptos OpenPGP). Mucha de Fase 1 es esperar a que la YubiKey procese.

---

## Referencias

- [drduh/YubiKey-Guide](https://github.com/drduh/YubiKey-Guide) — guía canónica de OpenPGP en YubiKey
- [Misterio77/nix-config](https://github.com/Misterio77/nix-config) — implementación de referencia que copiamos
- [home/gabriel/features/cli/gpg.nix](https://github.com/Misterio77/nix-config/blob/main/home/gabriel/features/cli/gpg.nix) — fichero específico
- [NixOS Wiki — YubiKey](https://wiki.nixos.org/wiki/Yubikey)
- [sops-nix README](https://github.com/Mic92/sops-nix)
