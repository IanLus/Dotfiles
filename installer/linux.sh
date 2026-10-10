if [[ ! -d /etc/zsh ]]; then
  echo "please install zsh and try again"
  exit 1
elif ! command -v git >/dev/null; then
  echo "please install git and try again"
  exit 1
fi
CONFIG_DIR="${XDG_CONFIG_HOME:-~/.config}"
DOTDIR="$CONFIG_DIR/dotfiles"
git clone https://github.com/wit-l/dotfiles "$DOTDIR"
echo "source $DOTDIR/common_shell_env/common_env" >>/etc/zsh/zshenv
ln -sf "$DOTDIR/git/gitconfig" ~/.gitconfig
if [[ ! -d ~/.ssh ]]; then mkdir ~/.ssh; fi
ln -sf "$DOTDIR/ssh/config" ~/.ssh
if command -v joshuto >/dev/null; then
  ln -sf "$DOTDIR/joshuto" "$CONFIG_DIR"
fi
if command -v ranger >/dev/null; then
  ln -sf "$DOTDIR/ranger" "$CONFIG_DIR"
fi
DATA_HOME="${XDG_DATA_HOME:-$CONFIG_DIR/local}"
mkdir -p "$DATA_HOME/dbus-1/services"
ln -sfn "$DOTDIR/xdg-data/dbus-1/services/org.freedesktop.FileManager1.service" \
  "$DATA_HOME/dbus-1/services/org.freedesktop.FileManager1.service"
echo "please reboot your system"
