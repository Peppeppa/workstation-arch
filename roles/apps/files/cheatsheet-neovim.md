# Neovim keybindings

Neovim with LazyVim, the workstation keymaps (`lua/config/keymaps.lua`)
and VimTeX - checked against the keymaps actually loaded on this setup.
**Leader** = `Space`, **local leader** = `\`. In LazyVim, press `Space` and
wait: which-key lists every group. Sources: **Vim** = built in,
**LazyVim** = LazyVim default, **workstation** = `keymaps.lua`,
**VimTeX** = only in `.tex` files.

## Modes and files (Vim)

| Key | Action |
| --- | --- |
| `i` / `a` | Insert before / after the cursor |
| `I` / `A` | Insert at line start / end |
| `o` / `O` | New line below / above |
| `v` / `V` | Visual: characters / lines |
| `Esc` | Back to normal mode (in normal mode: saves, see below) |
| `:w` / `:q` / `:wq` / `:q!` | Save / quit / save and quit / quit without saving |
| `u` / `Ctrl + r` | Undo / redo |
| `.` | Repeat the last change |

## Moving (Vim)

| Key | Action |
| --- | --- |
| `h` `j` `k` `l` | Left, down, up, right |
| `w` / `b` / `e` | Next word / previous word / word end |
| `0` / `^` / `$` | Line start / first character / line end |
| `gg` / `G` | First / last line |
| `{` / `}` | Previous / next paragraph |
| `%` | Matching bracket (VimTeX: matching environment too) |
| `f` `x` / `t` `x` | To / before the next `x` in the line |
| `Ctrl + o` / `Ctrl + i` | Back / forward in the jump list |

## Editing (Vim)

| Key | Action |
| --- | --- |
| `x` | Delete the character |
| `dd` / `yy` / `p` / `P` | Delete line / copy line / paste after / before |
| `d` `w`, `c` `w`, `y` `w` | Delete / change / copy a word (any motion works) |
| `ci"` / `da(` | Change inside quotes / delete around parentheses |
| `>>` / `<<` | Indent / outdent the line |
| `r` `x` | Replace one character with `x` |

## Search and replace (Vim)

| Key | Action |
| --- | --- |
| `/text` / `?text` | Search forward / backward |
| `n` / `N` | Next / previous hit (kept centered - workstation) |
| `*` / `#` | Word under the cursor forward / backward |
| `:%s/old/new/g` | Replace in the whole file (`gc` asks each time) |

## Workstation keymaps

| Key | Action |
| --- | --- |
| `Esc` (normal) | Save the file |
| `j` `k` (insert) | Leave insert mode |
| `Ctrl + d` / `Ctrl + u` | Half page down / up, centered |
| `J` (normal) | Join lines, cursor stays |
| `J` / `K` (visual) | Move the selected lines down / up |
| `Space y` / `Space Y` | Copy to the system clipboard (line: `Y`) |
| `Ctrl + c` (visual) | Copy to the system clipboard |
| `Ctrl + v` (normal) | Paste from the system clipboard (replaces visual block) |
| `Space p` (visual) | Paste over the selection, keep the copied text |
| `Space c` (visual) | Comment the lines with `#` |
| `Space x` | Make the file executable |
| `Space p v` | File explorer |
| `Ctrl + h / j / k / l` | Window left / down / up / right |

## LazyVim: files and search

| Key | Action |
| --- | --- |
| `Space Space` / `Space f f` | Find files (project) |
| `Space f r` | Recent files |
| `Space ,` / `Space f b` | Open buffers |
| `Space /` / `Space s g` | Search text in the project (grep) |
| `Space s r` | Search and replace (project) |
| `Space s k` | All keymaps |
| `Space s h` | Help pages |
| `Space e` / `Space E` | Explorer (project / current directory) |
| `Space f n` | New file |
| `s` | Flash: jump to any visible place |
| `Space u C` | Colorschemes |

## LazyVim: buffers and windows

| Key | Action |
| --- | --- |
| `Shift + h` / `Shift + l` | Previous / next buffer (also `[b` / `]b`) |
| `Space b b` / `` Space ` `` | Switch to the other buffer |
| `Space b d` / `Space b o` | Close buffer / close all other buffers |
| `Space -` / `Space \|` | Split below / right |
| `Space w d` | Close window |
| `Space w m` | Zoom window on/off |
| `Ctrl + s` | Save (normal, insert, visual) |
| `Space q q` | Quit all |

## LazyVim: code, git and tools

| Key | Action |
| --- | --- |
| `gc` `c` / `gc` (visual) | Comment line / selection |
| `Alt + j` / `Alt + k` | Move line or selection down / up |
| `Space c f` | Format |
| `Space c d` | Line diagnostics |
| `]d` / `[d` | Next / previous diagnostic |
| `Space x x` | Diagnostics list (Trouble) |
| `Space g g` | Lazygit |
| `Space g b` | Git blame of the line |
| `Space f t` | Terminal |
| `Space u w` / `Space u s` | Wrap on/off / spelling on/off |
| `Space l` | Lazy (plugins) |

## VimTeX (.tex files, local leader `\`)

| Key | Action |
| --- | --- |
| `\ll` | Compile on/off (latexmk, rebuilds on every save) |
| `\lk` | Stop compiling |
| `\lS` | Compile once |
| `\lv` | Show the PDF in Zathura at the cursor (forward search) |
| `\le` | Errors and warnings |
| `\lt` | Table of contents |
| `\li` | Information (project, compiler, viewer) |
| `\lq` | VimTeX log |
| `\lc` | Remove auxiliary files (PDF stays) |
| `\lC` | Remove auxiliary files and the PDF |
| `dse` / `cse` | Delete / change the surrounding environment |
| `dsc` / `csc` | Delete / change the surrounding command |
| `tse` | Toggle the environment (`itemize` <-> `enumerate`) |
| `ie` / `ae` (visual, operator) | Inside / around an environment |
| `]]` / `[[` | Next / previous section |
| `K` | Documentation of the package under the cursor |
