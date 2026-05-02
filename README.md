# tree.kak
Another filetree plugin for kakoune

https://github.com/user-attachments/assets/df0a21fe-69d5-43b4-b3ce-3462b3395a81

## Dependencies
- [tree](https://gitlab.com/OldManProgrammer/unix-tree)
- [tmux](https://github.com/tmux/tmux/) (optional)

## Installation
Copy [tree.kak](./tree.kak) into your autoload directory

## Usage
Run either `:tree-open` or `:tree-toggle` to get started

## Suggested Keymap
```kak
hook global WinSetOption filetype=tree %{
  try %{
    remove-highlighter window/wrap
  }

  map window normal <ret> ":tree-open<ret>"
  map window normal l ":tree-open<ret>"
  map window normal h "gg:tree-open<ret>"
  map window normal a ":tree-create<ret>"
  map window normal d ":tree-delete<ret>"
  map window normal y ":tree-copy<ret>"
  map window normal x ":tree-cut<ret>"
  map window normal p ":tree-paste<ret>"
  map window normal r ":tree-rename<ret>"
  map window normal c ":tree-cd<ret>"
  map window normal <esc> ":tree-clear-copy<ret>"
}
```

## Note

This configuration has been set on the filetree buffer to prevent accidental changes to the buffer
The buffer is the source of truth so if anything changes it outside of the tree commands, unwanted actions may be performed to your file system

```kak
hook global WinSetOption filetype=tree %{
  set-option window modelinefmt ''

  map window normal i ":nop<ret>"
  map window normal I ":nop<ret>"
  map window normal a ":nop<ret>"
  map window normal A ":nop<ret>"
  map window normal o ":nop<ret>"
  map window normal O ":nop<ret>"
  map window normal c ":nop<ret>"
  map window normal d ":nop<ret>"
  map window normal u ":nop<ret>"
  map window normal <a-d> ":nop<ret>"
  map window normal <a-c> ":nop<ret>"
  map window normal x ":nop<ret>"
  map window normal y ":nop<ret>"
  map window normal p ":nop<ret>"
  map window normal r ":nop<ret>"
  map window normal R ":nop<ret>"
}
```

## References
- [kaktree](https://github.com/andreyorst/kaktree/tree/master)
- [ptfm](https://gitlab.com/lisael/ptfm)

