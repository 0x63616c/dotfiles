# Homelab packages are owned by WWW's projects/homelab/modules/coding.nix.
# Use the stable system profile so upgrades do not leave hardcoded store paths.
# Do not run Homebrew shellenv here: Rex must retain its matching CLI first.
for plugin in \
  /run/current-system/sw/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /run/current-system/sw/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [[ ! -f "$plugin" ]] || source "$plugin"
done
unset plugin

# vov's tool from the ~/vov checkout: `vov` rebuilds when needed, else runs the cached binary.
[[ ! -d "$HOME/vov/bin" ]] || path+=("$HOME/vov/bin")

# Claude in ~/vov gets vov's MCP keys from sops, for that process only (see vov/.mcp.json).
claude() {
  if [[ $PWD == $HOME/vov(|/*) ]]; then
    PENPOT_MCP_KEY="$("$HOME/vov/bin/vov" admin secrets get access PENPOT_MCP_KEY 2>/dev/null)" command claude "$@"
  else
    command claude "$@"
  fi
}
