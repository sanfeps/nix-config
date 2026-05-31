{pkgs ? import <nixpkgs> {}, ...}: rec {
  # Packages with an actual source

  # Personal scripts
  generate-headscale-bootstrap-key =
    pkgs.writers.writePython3Bin "generate-headscale-bootstrap-key" {
      libraries = [pkgs.python3Packages.bcrypt];
    } ''
      import base64
      import secrets

      import bcrypt


      def b64url(n: int) -> str:
          raw = secrets.token_bytes(n)
          return base64.urlsafe_b64encode(raw).decode().rstrip("=")


      prefix = b64url(9)
      secret = b64url(48)
      digest = bcrypt.hashpw(secret.encode(), bcrypt.gensalt(10)).decode()
      full_key = f"hskey-auth-{prefix}-{secret}"

      print("=== Headscale bootstrap key generated ===\n")
      print("Paste into sops files exactly as shown:\n")
      print("1. hosts/common/secrets.yaml")
      print(f"   tailscale-preauth-key: {full_key}\n")
      print("2. hosts/asgard/secrets.yaml")
      print(f"   headscale-bootstrap-prefix: {prefix}")
      print(f"   headscale-bootstrap-hash: {digest}\n")
      print("Then deploy asgard first, then any client host.")
    '';

  # My slightly customized plymouth theme, just makes the blue outline white
}
