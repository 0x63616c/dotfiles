# Homelab packages are owned by WWW's projects/homelab/modules/coding.nix.
# Use the stable system profile so upgrades do not leave hardcoded store paths.
# Do not run Homebrew shellenv here: Rex must retain its matching CLI first.
for plugin in \
  /run/current-system/sw/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /run/current-system/sw/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [[ ! -f "$plugin" ]] || source "$plugin"
done
unset plugin
