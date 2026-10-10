if [[ ! -d /etc/zsh ]]; then
  echo "please install zsh and try again"
  exit 1
elif ! command -v git >/dev/null; then
  echo "please install git and try again"
  exit 1
fi
CONFIG_DIR="${XDG_CONFIG_HOME:-~/.config}"
DOTDIR="$CONFIG_DIR/dotfiles"
if [[ -e "$DOTDIR" && ! -d "$DOTDIR/.git" ]]; then
  echo "$DOTDIR exists but is not a git checkout" >&2
  exit 1
elif [[ ! -d "$DOTDIR/.git" ]]; then
  git clone https://github.com/wit-l/dotfiles "$DOTDIR"
fi
env_file="$DOTDIR/zsh/env.zsh"
if ! grep -qF "$env_file" /etc/zsh/zshenv; then
  echo "source $env_file" >>/etc/zsh/zshenv
fi
ln -sf "$DOTDIR/git/gitconfig" ~/.gitconfig
if [[ ! -d ~/.ssh ]]; then mkdir ~/.ssh; fi
ln -sf "$DOTDIR/ssh/config" ~/.ssh
if command -v joshuto >/dev/null; then
  ln -sf "$DOTDIR/joshuto" "$CONFIG_DIR"
fi
if command -v ranger >/dev/null; then
  ln -sf "$DOTDIR/ranger" "$CONFIG_DIR"
fi
if command -v kitty >/dev/null; then
  mkdir -p "$CONFIG_DIR/xfce4"
  ln -sfn "$DOTDIR/xfce4/helpers.rc" "$CONFIG_DIR/xfce4/helpers.rc"
fi
DATA_HOME="${XDG_DATA_HOME:-$CONFIG_DIR/local}"
mkdir -p "$DATA_HOME/dbus-1/services"
ln -sfn "$DOTDIR/xdg-data/dbus-1/services/org.freedesktop.FileManager1.service" \
  "$DATA_HOME/dbus-1/services/org.freedesktop.FileManager1.service"
echo "please reboot your system"
