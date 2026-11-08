# fzf-tab 预览笔记

记录 fzf-tab 预览规则的踩坑与验证方法。规则本体在 `zsh/zshrc.zsh`，
这里只写「为什么这么写」和「怎么验」。

## systemctl 单元预览

```zsh
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview \
  '[[ -n $word ]] && SYSTEMD_COLORS=1 SYSTEMD_URLIFY=0 systemctl ${${words[(Ie)--user]:#0}:+--user} status -- "$word"'
```

### --user 为什么绕两层

`systemctl --user status <Tab>` 补出的候选是用户单元，原来的预览固定跑
`systemctl status`（系统管理器），这些单元在系统侧不存在，预览只剩一句
`Unit ... could not be found.`。

判断「命令行上有没有 --user」时不能直接写 `:+--user`：

- `words[(Ie)--user]` 没命中时返回下标 `0`
- `0` 是非空字符串，`:+--user` 会把它当成「有 --user」
- 结果：系统单元全被送进用户管理器，反而全查不到

所以先 `:#0` 把 `0` 转成空串，再 `:+--user`：

```zsh
${${words[(Ie)--user]:#0}:+--user}
```

### 空候选保护

`[[ -n $word ]]` 不是防御性冗余。光标停在命令位或选项位时 `word` 是空的，
此时 `systemctl status` 会打印整机摘要：

```
● 主机名
    State: running
    Units: 415 loaded (incl. loaded aliases)
```

看着像有预览，其实跟当前候选毫无关系，反而掩盖了「这里不该有预览」。

### SYSTEMD_URLIFY=0

预览是管道，systemd 默认输出 OSC 8 超链接转义序列，fzf 渲染不出来，
显示成乱码。关掉。

### 没写 --user 时用户侧独有单元查不到

`systemctl status pipewire.serv<Tab>` 仍显示 `could not be found.`。
这不是预览的问题：`_systemctl` 在系统模式下不会把用户单元列为候选，
`systemctl status pipewire.service` 本身就是这个输出。
要覆盖得在查不到时回落另一个管理器，代价是每次预览多跑一次 `systemctl`，
目前不做。

## 怎么验证这类规则

**别只在交互 shell 里调函数。** 预览命令由 fzf-tab 用
`zsh -c "<init>\n<command>"` 起子进程执行，真实作用域只有 init 里定义的那些变量；
`word`、`group`、`words` 的实际取值和直接写脚本试并不一致。

一条可直接套用的流程：

1. **读回规则**，确保验的是配置里的真货，而不是手抄的副本：

   ```zsh
   zstyle -s ':fzf-tab:complete:systemctl-status:' fzf-preview rule
   ```

2. **造 compcap 记录**，格式照 `fzf-tab.zsh` 里
   `_ftb_compcap+=$dscr$'\2'$__tmp_value$'\0word\0'$word`：

   - 分隔符是 `\2`（描述与值之间）和 `\0`（键值对之间）
   - `__tmp_value` 以 `<\0>` 占位开头。少了它拼出来是奇数个字段，
     init 会报 `bad set of key/value pairs for associative array`
   - 同理末尾**不要**多补 `\0`，多一个也是奇数个字段，报同样的错

   正确形状（`<\0>` 是字面的 `<`、`>` 两个字段，用来凑成偶数）：

   ```zsh
   printf '%s\2%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s' \
     "$dscr" '<' '>' group 1 args '' word "$cand"
   ```

3. **拼 init**：读 `lib/-ftb-preview.tpl`，按 `-ftb-fzf` 的做法替换
   `__FTB_COMPCAP__`、`__FTB_GROUPS__`、`__FTB_WORDS_DUMP__`、`{f}`；
   `words` 用 `typeset -p words` 注入。

4. **按 fzf 的方式执行**：`zsh -c "<init>\n<规则>" <候选>`，检查 stdout。

至少覆盖这几类：

| 场景 | 期望 |
| --- | --- |
| `--user` + 用户单元 | 正常 status 输出 |
| 无 `--user` + 系统单元 | 正常 status 输出 |
| `--user` + 系统单元 | 走用户管理器，输出 D-Bus User Message Bus 之类 |
| 空 `word`（命令位/选项位） | 无输出 |
| 不存在的单元 | `could not be found.` |

### 一个反例

先前一版加了这样的守卫：

```zsh
(( $#positional >= 2 )) || return 0
```

预览进程里 `words` 的末位是空串（`systemctl status <光标处空>` →
`WORDS=(systemctl|status|)`），剥掉命令名后元素个数对不上，这个条件对
**所有**情况都判假，函数直接返回，预览永远是空的 —— 系统单元、`--user`、
`cat`、`show` 一起坏掉。当时还只在自己造的数组上调函数，没能发现。

结论：任何「取 words 第 N 位当子命令/单元名」的写法，都要考虑末位空串。

## zwc 缓存

`zsh/zshrc.zsh` 由 zinit 的 `atinit"zicompinit; source $ZDOTDIR/zshrc.zsh"`
加载，每次启动都会重新生成 `zshrc.zsh.zwc`。zsh 优先读 zwc，源文件更新但
zwc 还是旧的时会读到旧配置。排查「改了没生效」先看：

```zsh
ls -la zsh/zshrc.zsh zsh/zshrc.zsh.zwc
```
