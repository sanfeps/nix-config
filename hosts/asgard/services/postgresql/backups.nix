{
  config,
  pkgs,
  ...
}: let
  backupDir = "/var/backups/postgres";
  retentionDays = 90;

  pgBackup = pkgs.writeShellApplication {
    name = "postgres-backup";
    runtimeInputs = with pkgs; [postgresql_17 coreutils findutils];
    text = ''
      set -euo pipefail

      backup_root=${backupDir}
      retention=${toString retentionDays}
      timestamp=$(date +%Y%m%d-%H%M%S)

      databases=$(psql -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';")

      for db in $databases; do
        target_dir="$backup_root/$db"
        mkdir -p "$target_dir"
        pg_dump --format=custom --file="$target_dir/$db-$timestamp.dump" "$db"
        find "$target_dir" -type f -name "*.dump" -mtime "+$retention" -delete
      done
    '';
  };
in {
  systemd.tmpfiles.rules = [
    "d ${backupDir} 0700 postgres postgres -"
  ];

  systemd.services.postgres-backup = {
    description = "Dump every PostgreSQL database with rotation";
    after = ["postgresql.service"];
    requires = ["postgresql.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
      ExecStart = "${pgBackup}/bin/postgres-backup";
    };
  };

  systemd.timers.postgres-backup = {
    description = "Daily PostgreSQL backup timer";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  environment.persistence."${config.hostSpec.persistFolder}".directories = [
    {
      directory = backupDir;
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
  ];
}
