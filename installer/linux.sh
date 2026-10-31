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
  git clone https://github.com/IanLus/dotfiles "$DOTDIR"
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

# 已有的普通文件留在原地，避免装机时盖掉本机改过的配置。
link_config() {
  local src="$1" dest="$2"
  mkdir -p -- "$(dirname -- "$dest")"
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    echo "keep existing $dest" >&2
    return 0
  fi
  ln -sfn "$src" "$dest"
}

link_config "$DOTDIR/fontconfig" "$CONFIG_DIR/fontconfig"
link_config "$DOTDIR/environment.d/90-dms.conf" "$CONFIG_DIR/environment.d/90-dms.conf"
link_config "$DOTDIR/gtk-3.0/settings.ini" "$CONFIG_DIR/gtk-3.0/settings.ini"
link_config "$DOTDIR/gtk-3.0/gtk.css" "$CONFIG_DIR/gtk-3.0/gtk.css"
link_config "$DOTDIR/gtk-3.0/bookmarks" "$CONFIG_DIR/gtk-3.0/bookmarks"
link_config "$DOTDIR/gtk-4.0/settings.ini" "$CONFIG_DIR/gtk-4.0/settings.ini"
link_config "$DOTDIR/gtk-4.0/gtk.css" "$CONFIG_DIR/gtk-4.0/gtk.css"
link_config "$DOTDIR/mimeapps.list" "$CONFIG_DIR/mimeapps.list"
link_config "$DOTDIR/user-dirs.dirs" "$CONFIG_DIR/user-dirs.dirs"
link_config "$DOTDIR/user-dirs.locale" "$CONFIG_DIR/user-dirs.locale"
link_config "$DOTDIR/xdg-terminals.list" "$CONFIG_DIR/xdg-terminals.list"
link_config "$DOTDIR/xfce4/help.rc" "$CONFIG_DIR/xfce4/help.rc"

if command -v cava >/dev/null; then
  link_config "$DOTDIR/cava" "$CONFIG_DIR/cava"
fi
if command -v dsearch >/dev/null; then
  link_config "$DOTDIR/dsearch" "$CONFIG_DIR/dsearch"
fi
if command -v dcal >/dev/null; then
  link_config "$DOTDIR/dankcal" "$CONFIG_DIR/dankcal"
fi
if command -v trans >/dev/null; then
  link_config "$DOTDIR/translate-shell" "$CONFIG_DIR/translate-shell"
fi
if command -v nwg-look >/dev/null; then
  link_config "$DOTDIR/nwg-look" "$CONFIG_DIR/nwg-look"
fi
if command -v nwg-look >/dev/null || command -v xsettingsd >/dev/null; then
  link_config "$DOTDIR/xsettingsd" "$CONFIG_DIR/xsettingsd"
fi
if command -v qt5ct >/dev/null; then
  link_config "$DOTDIR/qt5ct" "$CONFIG_DIR/qt5ct"
fi
if command -v qt6ct >/dev/null; then
  link_config "$DOTDIR/qt6ct/qt6ct.conf" "$CONFIG_DIR/qt6ct/qt6ct.conf"
fi
if command -v wps >/dev/null; then
  link_config "$DOTDIR/kingsoft.conf" "$CONFIG_DIR/kingsoft.conf"
fi
if command -v clash-verge >/dev/null; then
  link_config "$DOTDIR/autostart/Clash Verge.desktop" "$CONFIG_DIR/autostart/Clash Verge.desktop"
fi
if command -v dms >/dev/null; then
  link_config "$DOTDIR/dms/settings.json" "$CONFIG_DIR/dms/settings.json"
  link_config "$DOTDIR/dms/plugin_settings.json" "$CONFIG_DIR/dms/plugin_settings.json"
  link_config "$DOTDIR/dms/plugins.lock.json" "$CONFIG_DIR/dms/plugins.lock.json"
  link_config "$DOTDIR/dms/monitors.json" "$CONFIG_DIR/dms/monitors.json"
fi
if command -v udiskie >/dev/null; then
  link_config "$DOTDIR/systemd/user/udiskie.service" "$CONFIG_DIR/systemd/user/udiskie.service"
  if ! systemctl --user enable udiskie.service; then
    mkdir -p "$CONFIG_DIR/systemd/user/graphical-session.target.wants"
    ln -sfn "$CONFIG_DIR/systemd/user/udiskie.service" \
      "$CONFIG_DIR/systemd/user/graphical-session.target.wants/udiskie.service"
  fi
fi

echo "please reboot your system"
