# Headscale + Tailscale

This repo is set up to use a self-hosted Headscale control plane with Tailscale
clients on `midgard` and `raidho`.

## Current domains

- Login server: `https://headscale.valgrindr.net`
- MagicDNS tailnet domain: `yggdrasil.local`

That means hosts should end up reachable as:

- `midgard.yggdrasil.local`
- `raidho.yggdrasil.local`
- future hosts as `<host>.yggdrasil.local`

## How the client side works

The shared client module is `hosts/optional/tailscale.nix`.

It does three things:

1. Enables `tailscaled`
2. Creates `/persist/secrets`
3. Starts `tailscale-autoconnect-valgrindr.service` if
   `/persist/secrets/tailscale-auth-key` exists

The auth key is intentionally kept out of the Nix store.

## One-time setup on the Headscale server

Create the user once:

```sh
sudo headscale users create yggdrasil
```

Then create a preauth key whenever you want to enroll a host:

```sh
sudo headscale preauthkeys create --user yggdrasil --expiration 24h
```

You can use `--reusable` if you want to keep a longer-lived bootstrap key, but
single-use keys are safer.

## Enroll a host

From this repo, run:

```sh
./scripts/install-tailscale-auth-key.sh --target root@midgard
```

The script will ask for the auth key, install it to
`/persist/secrets/tailscale-auth-key`, and restart the auto-connect service.

For `raidho`, for example:

```sh
./scripts/install-tailscale-auth-key.sh --target root@raidho
```

If you are already on the target host, you can also do it locally:

```sh
printf '%s\n' 'tskey-...' | sudo tailscale-auth-key-install-valgrindr
```

## Verify

On the host you just enrolled:

```sh
tailscale status
getent hosts midgard.yggdrasil.local
```

On another mesh host:

```sh
ping midgard.yggdrasil.local
ssh sanfe@midgard.yggdrasil.local
```

For Moonlight:

```sh
moonlight-pair-midgard
moonlight-stream-midgard
```

## Adding future hosts

1. Add the new NixOS host to the repo
2. Import `../optional/tailscale.nix`
3. Rebuild the host
4. Create a fresh Headscale preauth key
5. Install it with `scripts/install-tailscale-auth-key.sh`
6. Confirm the host appears in `headscale nodes list`

## Future hardening

The current setup is "declarative except for the bootstrap secret". A future
upgrade path is to re-enable `sops-nix` and store per-host auth keys encrypted
to host keys, but that is not wired in this step.
