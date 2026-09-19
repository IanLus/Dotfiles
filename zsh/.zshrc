# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.config/zsh/.zshrc.
# NOTE: Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# For testing plugin performance with zsh/zprof
# zmodload zsh/zprof
module_path+=( "$XDG_DATA_HOME/zinit/module/Src" )
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
  atload'source $ZDOTDIR/p10k.zsh' \
    romkatv/powerlevel10k \
  lucid \
    zdharma-continuum/zinit-annex-bin-gem-node

zinit wait lucid light-mode for \
  OMZL::history.zsh \
  OMZL::git.zsh \
  OMZP::git/git.plugin.zsh \
  if'command -v docker &>/dev/null' \
    OMZP::docker/docker.plugin.zsh \
    OMZP::docker-compose/docker-compose.plugin.zsh \
  atclone"sed -i '105,108s/\\\e\\\e/\\^o/g' sudo.plugin.zsh" \
  nocompile"!" atpull"%atclone" \
    OMZP::sudo/sudo.plugin.zsh \
  atclone"mkdir -p ~/.config/ranger/plugins;mv ranger_zlua.py ~/.config/ranger/plugins/" \
  atload"export RANGER_ZLUA='$ZINIT[PLUGINS_DIR]/skywind3000---z.lua/z.lua'" \
  atpull'!git reset --hard' \
    skywind3000/z.lua \
  hlissner/zsh-autopair

# install manual and scripts
zinit wait lucid as"null" light-mode for \
  atclone"chmod a+x fzf-preview.sh;mkdir -p $ZPFX/bin;mv fzf-preview.sh $ZPFX/bin/" atpull"%atclone" id-as"fzf-preview.sh" \
    https://fastly.jsdelivr.net/gh/junegunn/fzf/bin/fzf-preview.sh

# completions
zinit wait lucid light-mode as"completion" blockf for \
  atpull'zinit creinstall -q .' \
    zsh-users/zsh-completions \
  has'conda' \
    conda-incubator/conda-zsh-completion \
  has'fzf' id-as'_fzf' \
    https://fastly.jsdelivr.net/gh/wit-l/Dotfiles@main/completions/fzf/_fzf \
  has'eza' id-as'_eza' \
    https://fastly.jsdelivr.net/gh/eza-community/eza@main/completions/zsh/_eza \
  has'rustc' id-as'_rustc' \
    OMZP::rust/_rustc \
  has'docker' id-as'_docker' \
    OMZP::docker/completions/_docker \
  has'docker' id-as'_docker-compose' \
    OMZP::docker-compose/_docker-compose \
  has'rustup' id-as'_rustup' \
    $DOTDIR/completions/rust/_rustup \
  has'cargo' id-as'_cargo' \
    $DOTDIR/completions/rust/_cargo \
  has'joshuto' id-as'_joshuto'\
    $DOTDIR/completions/joshuto/_joshuto \
  has'yq' id-as'_yq'\
    $DOTDIR/completions/yq/_yq \
  has'delta' id-as'_delta'\
    https://fastly.jsdelivr.net/gh/dandavison/delta@main/etc/completion/completion.zsh \
  has'npm' compile'_npm' \
    Ajnasz/zsh-npm-completion \
  has'pnpm' compile'completions/_pnpm' \
    empresslabs/pnpm.plugin.zsh \
  has'dms' id-as'_dms' \
    $DOTDIR/completions/dms/_dms \
  has'niri' id-as'_niri' \
    $DOTDIR/completions/niri/_niri

zinit wait lucid light-mode for \
  blockf atinit"zicompinit; source $ZDOTDIR/zshrc.zsh" \
    Aloxaf/fzf-tab \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  atload"zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting
# zprof
