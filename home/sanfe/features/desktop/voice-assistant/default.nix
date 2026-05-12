{pkgs, ...}: let
  voice-assistant = pkgs.writeShellApplication {
    name = "voice-assistant";
    runtimeInputs = with pkgs; [
      whisper-cpp
      piper-tts
      pulseaudio # parec
      pipewire # pw-cat
      claude-code # the agent that handles the prompt
      jq
      curl
      libnotify
      coreutils
      findutils
      gnused
    ];
    text = builtins.readFile ./voice-assistant.sh;
  };
in {
  home.packages = [voice-assistant];

  home.persistence."/persist".directories = [
    ".cache/voice-assistant" # whisper + piper models (~1.5GB)
    ".local/share/voice-assistant" # data
    ".local/state/voice-assistant" # workspace cwd + logs (claude sessions live in ~/.claude, already persisted)
  ];
}
