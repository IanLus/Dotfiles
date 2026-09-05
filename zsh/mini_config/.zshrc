# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.config/zsh/.zshrc.
# NOTE: Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi
module_path+=( "${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/module/Src" )
zmodload zdharma_continuum/zinit
setopt prompt_subst histignorealldups sharehistory HIST_SAVE_NO_DUPS # Do not write a duplicate event to the history file.
setopt AUTO_PUSHD           # Push the current directory visited on the stack.
setopt PUSHD_IGNORE_DUPS    # Do not store duplicates in the stack.
setopt PUSHD_SILENT         # Do not print the directory stack after pushd or popd.

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -f $ZINIT_HOME/zinit.zsh ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "$ZINIT_HOME/zinit.zsh" # 加载zinit的初始化脚本

zinit depth'1' light-mode for \
  atload'source $ZINIT[PLUGINS_DIR]/romkatv---powerlevel10k/config/p10k-robbyrussell.zsh' \
    romkatv/powerlevel10k \
  lucid \
    zdharma-continuum/zinit-annex-bin-gem-node

zinit wait lucid light-mode for \
  OMZL::history.zsh \
  OMZL::git.zsh \
  OMZP::git/git.plugin.zsh \
  atclone"sed -i '105,108s/\\\e\\\e/\\^o/g' sudo.plugin.zsh" \
  nocompile"!" atpull"%atclone" \
    OMZP::sudo/sudo.plugin.zsh \
  skywind3000/z.lua \
  hlissner/zsh-autopair

zinit wait lucid light-mode from"gh-r" completions blockf for \
  mv"ripgrep*/doc/rg.1 -> $ZINIT[MAN_DIR]/man1/" compile"ripgrep*/complete/_rg" \
    sbin"ripgrep*/rg"       BurntSushi/ripgrep \
  mv"fd*/fd.1 -> $ZINIT[MAN_DIR]/man1/" compile"fd*/autocomplete/_fd" \
    sbin"fd*/fd"            @sharkdp/fd \
  mv"hyperfine*/hyperfine.1 -> $ZINIT[MAN_DIR]/man1/" compile"hyperfine*/autocomplete/_hyperfine" \
    sbin"hyperfine"         @sharkdp/hyperfine \
  mv"bat*/autocomplete/bat.zsh -> _bat" compile"_bat" \
  atclone"mv bat*/bat.1 $ZINIT[MAN_DIR]/man1/" atpull"%atclone" \
    sbin"bat*/bat"          @sharkdp/bat \
  atload"alias ls='eza -g -F auto'" \
    sbin"eza"               @eza-community/eza \
  atload"source $XDG_CONFIG_HOME/.fzf.zsh" \
    as"program"             junegunn/fzf

# install scripts
zinit wait lucid as"null" light-mode for \
  mv"fzf.1 -> $ZINIT[MAN_DIR]/man1/" id-as"fzf.1" \
    https://raw.githubusercontent.com/junegunn/fzf/master/man/man1/fzf.1 \
  mv"fzf-tmux.1 -> $ZINIT[MAN_DIR]/man1/" id-as"fzf-tmux.1" \
    https://raw.githubusercontent.com/junegunn/fzf/master/man/man1/fzf-tmux.1 \
  from"gh-r" bpick"man*" mv"target/man*/eza.1 -> $ZINIT[MAN_DIR]/man1/" \
  atclone"mv target/man*/*.5 $ZINIT[MAN_DIR]/man5/" atpull"%atclone" id-as"eza-man" \
    @eza-community/eza \
  atclone"chmod a+x fzf-preview.sh;mv fzf-preview.sh $ZPFX/bin/" atpull"%atclone" id-as"fzf-preview.sh" \
    https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-preview.sh \
  atclone"chmod a+x fzf-tmux;mv fzf-tmux $ZPFX/bin/" atpull"%atclone" id-as"fzf-tmux" \
    https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-tmux

zinit wait lucid light-mode as="completion" blockf for \
  atpull'zinit creinstall -q .' \
    zsh-users/zsh-completions \
  has'conda' \
    conda-incubator/conda-zsh-completion \
  has'fzf' id-as'_fzf' \
    https://raw.githubusercontent.com/lmburns/dotfiles/master/.config/zsh/completions/_fzf \
  has'eza' id-as'_eza' \
    https://raw.githubusercontent.com/wit-l/Dotfiles/main/eza/_eza

zinit wait lucid light-mode for \
  blockf atinit"zicompinit" \
    Aloxaf/fzf-tab \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  atload"zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting

bindkey -v # CLI可使用vim模式
export KEYTIMEOUT=1
# Emacs
bindkey '^F' forward-char
bindkey '^p' up-line-or-search
bindkey '^n' down-line-or-search
bindkey '^w' backward-kill-word
bindkey '^u' backward-kill-line
bindkey '^y' yank
bindkey '^a' beginning-of-line
bindkey '^e' end-of-line
bindkey '^q' push-line-or-edit
bindkey '^k' kill-line
bindkey '\eb' backward-word
bindkey '^b' backward-char
bindkey '\ef' forward-word

# 根据不同的 vi 模式更改光标形状
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]] || [[ $1 == 'block' ]]; then
    echo -ne '\e[1 q'  # 使用 Filled box 形状
  elif [[ $KEYMAP == main ]] || [[ $KEYMAP == viins ]] || [[ $KEYMAP == '' ]] || [[ $1 == 'beam' ]]; then
    echo -ne '\e[5 q'  # 使用 bar 形状
  fi
}
zle -N zle-keymap-select
# 在启动时使用 bar 形状的光标
echo -ne '\e[5 q'

# == fzf-tab
zstyle ':fzf-tab:complete:_zlua:*' query-string input
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm,cmd -w -w"
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags '--preview-window=down:3:wrap'
zstyle ':fzf-tab:complete:kill:*' popup-pad 0 3
zstyle ':fzf-tab:complete:cd:*' popup-pad 30 0
zstyle ":fzf-tab:*" fzf-flags --color=bg+:23
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
zstyle ':completion:*' file-sort modification
zstyle ':completion:*:eza' sort false
zstyle ':completion:files' sort false
# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set descriptions format to enable group support
# NOTE: don't use escape sequences here, fzf-tab will ignore them
zstyle ':completion:*:descriptions' format '[%d]'
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
zstyle ':completion:*' menu no
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 -a --color=always $realpath'
# switch group using `<` and `>`
zstyle ':fzf-tab:*' switch-group '<' '>'
# default active-group-style is bold, too faint on already-colored headers
zstyle ':fzf-tab:*' active-group-style bold underline

# set case insensitive when change directory with cd
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'

[ -f $XDG_CONFIG_HOME/.aliases ] && source $XDG_CONFIG_HOME/.aliases
# make instant prompt quiet if console output during zsh initialization
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
