{pkgs, ...}: let
  voice-assistant = pkgs.writeShellApplication {
    name = "voice-assistant";
    runtimeInputs = with pkgs; [
      whisper-cpp
      piper-tts
      pulseaudio # parec
      pipewire # pw-cat
      jq
      curl
      libnotify
      coreutils
    ];
    text = builtins.readFile ./voice-assistant.sh;
  };
in {
  home.packages = [voice-assistant];

  home.persistence."/persist".directories = [
    ".cache/voice-assistant" # whisper + piper models (~1.5GB)
    ".local/share/voice-assistant" # conversation history
    ".config/voice-assistant" # api-key file (until migrated to sops)
  ];
}
