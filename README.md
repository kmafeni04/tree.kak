# tree.kak
Another filetree plugin for kakoune

![preview](./preview.mp4)

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
    remove-highlighter buffer/wrap
  }

  map buffer normal <ret> ":tree-open<ret>"
  map buffer normal l ":tree-open<ret>"
  map buffer normal h "gg:tree-open<ret>"
  map buffer normal a ":tree-create<ret>"
  map buffer normal d ":tree-delete<ret>"
  map buffer normal y ":tree-copy<ret>"
  map buffer normal x ":tree-cut<ret>"
  map buffer normal p ":tree-paste<ret>"
  map buffer normal r ":tree-rename<ret>"
  map buffer normal c ":tree-cd<ret>"
  map buffer normal <esc> ":tree-clear-copy<ret>"
}
```

## Note

This configuration has been set on the filetree buffer to prevent accidental changes to the to the buffer, the buffer is the source of truth so if anything changes to it, unwanted actions may be performed to your file system

```kak
hook global WinSetOption filetype=tree %{
  set-option buffer modelinefmt ''

  map buffer normal i ":nop<ret>"
  map buffer normal I ":nop<ret>"
  map buffer normal a ":nop<ret>"
  map buffer normal A ":nop<ret>"
  map buffer normal o ":nop<ret>"
  map buffer normal O ":nop<ret>"
  map buffer normal c ":nop<ret>"
  map buffer normal d ":nop<ret>"
  map buffer normal <a-d> ":nop<ret>"
  map buffer normal <a-c> ":nop<ret>"
  map buffer normal x ":nop<ret>"
  map buffer normal y ":nop<ret>"
  map buffer normal p ":nop<ret>"
  map buffer normal r ":nop<ret>"
  map buffer normal R ":nop<ret>"
}
```

## References
- [kaktree](https://github.com/andreyorst/kaktree/tree/master)
- [ptfm](https://gitlab.com/lisael/ptfm)

