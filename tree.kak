provide-module tree %{
  declare-option -hidden str _tree_current_dir "."
  declare-option -hidden str _tree_ui_cmd "echo '../'; tree -a --noreport --dirsfirst -L 1 --compress 2 -F"
  declare-option -hidden str _tree_jump_client "treejumpclient"
  declare-option -hidden str _tree_client "treeclient"
  declare-option -hidden str _tree_copied_filepath
  declare-option -hidden str _tree_copied_action
  declare-option -hidden str _tree_copied_indicator "\*"
  declare-option -hidden str _tree_hline_face "default,default+@SecondarySelection"

  define-command -hidden _tree-assert-buffer %{
    evaluate-commands %sh{
      if [ ! "$kak_bufname" = "*tree*" ]; then
        echo "fail 'Not in "*tree*" buffer'"
      fi
    }
  }

  define-command -hidden _tree-hline %{
    set-face buffer PrimaryCursor %opt{_tree_hline_face}
    set-face buffer PrimaryCursorEol %opt{_tree_hline_face}
    try %{ remove-highlighter buffer/hlline }
    try %{ add-highlighter buffer/hlline line %val{cursor_line} %opt{_tree_hline_face} }
  }

  define-command tree-redraw -docstring 'Redraw the filetree' -params ..1 %{
    _tree-assert-buffer
    evaluate-commands -save-regs 'c' %sh{
      if [ -n "$1" ]; then
        kak_opt__tree_current_dir="$1"
        echo "set-option buffer _tree_current_dir '$1'"
      fi
      cd "$kak_opt__tree_current_dir"

      ui_tree="$(
        eval "$kak_opt__tree_ui_cmd" |
        sed -E "2s|\.|$(basename "$kak_opt__tree_current_dir")|;s|(.+)( -> .+/)|\1/\2|g;s:[=\*>\|]$::g"
      )"

      if [ -n "$kak_opt__tree_copied_filepath" ] && [ "$kak_opt__tree_current_dir" = "$(dirname "$kak_opt__tree_copied_filepath")" ]; then
        ui_tree="$(echo "$ui_tree" | sed -E "s|^.(.+ $(basename "$kak_opt__tree_copied_filepath"))|$kak_opt__tree_copied_indicator\1|")"
      fi

      echo "set-register c '$ui_tree'"
      echo "execute-keys '%%<dquote>cR:select $kak_selection_desc<ret>'"
    }
    _tree-hline
  }

  define-command -hidden _tree-enable-impl -params 1 %{
      edit -scratch -debug "*tree*"
      set-option buffer filetype tree
      rename-client "%opt{_tree_client}"
      execute-keys "gg"
      tree-redraw %arg{1}
  }

  define-command tree-enable -docstring 'Open the filetree' %{
    try %{
      tree-disable
    }
    set-option global _tree_jump_client "%val{client}"
    evaluate-commands %sh{
      dir=
      [ -f "$kak_buffile" ] && dir="$(dirname "$kak_buffile")" || dir="$PWD"
      if [ -n "$TMUX" ]; then
        tmux split-window -l "20%" -h -b "kak -c $kak_session -e '_tree-enable-impl %{$dir}'" > /dev/null
      else
        echo "new '_tree-enable-impl %{$dir}'"
      fi
    }
  }

  define-command tree-disable -docstring 'Close the filetree' %{
    delete-buffer "*tree*"
    try %{
      evaluate-commands -client %opt{_tree_client} quit
    }
  }

  define-command tree-toggle -docstring 'Toggle visibility of filetree' %{
    try %{
      tree-disable
    } catch %{
      tree-enable
    }
  }

  define-command tree-open -docstring 'Open a file' %{
    _tree-assert-buffer
    evaluate-commands %sh{
      open(){
        local filepath="$1"

        if [ -d "$filepath" ]; then
          cd "$filepath"
          echo "set-option buffer _tree_current_dir \"$PWD\""
          echo "execute-keys gg"
        elif [ -f "$filepath" ]; then
          filepath="$kak_opt__tree_current_dir/$filepath"

          if [ -n "$(echo "$kak_client_list" | grep -o "$kak_opt__tree_jump_client")" ]; then
            echo "evaluate-commands -client $kak_opt__tree_jump_client %{ edit -existing "$filepath" }" | kak -p $kak_session
            if [ -n "$TMUX" ]; then
              echo "focus $kak_opt__tree_jump_client"
            fi
          else
            cmd="kak -c $kak_session -e 'edit -existing "$filepath"; rename-client "$kak_opt__tree_jump_client"'"
            if [ -n "$TMUX" ]; then
              tmux split-window -c "$dir" -l "80%" -h "$cmd" > /dev/null
            elif [ -n "$kak_opt_termcmd" ]; then
              $kak_opt_termcmd "cd $dir; $cmd"
            elif [ -n "$TERMINAL" ]; then
              $TERMINAL -e sh -c "cd $dir; $cmd" || $TERMINAL -x sh -c "cd $dir; $cmd" || $TERMINAL sh -c "cd $dir; $cmd"
            else
              echo "fail 'No defined method to run program'"
            fi
          fi
        fi
      }

      cd "$kak_opt__tree_current_dir"
      ui_tree="$(eval $kak_opt__tree_ui_cmd)"
      current_file="$(echo "$ui_tree" | head -$kak_cursor_line | tail -1 | grep -Po "[\.\w-].*")"

      if [ -n "$(echo "$current_file" | grep " -> ")" ]; then
        original="$(echo "$current_file" | awk -F' -> ' '{print $1}')"
        target="$(echo "$current_file" | awk -F' -> ' '{print $2}')"
        if [ -f "$target" ]; then
          open "$target"
        elif [ -d "$target" ]; then
          cd "$original"
          echo "set-option buffer _tree_current_dir \"$PWD\""
          echo "execute-keys gg"
        fi
      else
        open "$current_file"
      fi
    }
    tree-redraw
  }

  define-command tree-create -docstring 'Create a file' %{
    _tree-assert-buffer
    evaluate-commands %{
      prompt "Create:" %{
        evaluate-commands %sh{
          cd "$kak_opt__tree_current_dir"
          if [ -n "$(echo "$kak_text" | grep '.*/')" ]; then
            mkdir -p "$kak_text"
          else
            DIR_PATH=$(dirname "$kak_text")
            mkdir -p "$DIR_PATH"
            touch "$kak_text"
          fi
        }
        tree-redraw
      }
    }
  }

  define-command tree-delete -docstring 'Delete a file' %{
    _tree-assert-buffer
    prompt "Confirm Deletion [y/n]:" %{
      evaluate-commands %sh{
        if [ ! "$kak_text" = "y" ] || [ ! "$kak_text" = "Y"]; then
          exit
        fi
        cd "$kak_opt__tree_current_dir"
        ui_tree="$(eval $kak_opt__tree_ui_cmd)"
        current_file="$(echo "$ui_tree" | head -$kak_cursor_line | tail -1 | grep -Po "[\.\w-].*")"
        if [ -n "$(echo "$current_file" | grep " -> ")" ]; then
          current_file="$(echo "$current_file" | awk -F' -> ' '{print $1}')"
        fi

        if [ -x "$(command -v trash-put)" ]; then
          trash-put "$current_file"
        else
          rm -rf "$current_file"
        fi
      }
      tree-redraw
    }
  }

  define-command -hidden _tree-get-copy-cut-path -params 1 %{
    evaluate-commands %sh{
      cd "$kak_opt__tree_current_dir"
      ui_tree="$(eval $kak_opt__tree_ui_cmd)"
      current_file="$(echo "$ui_tree" | head -$kak_cursor_line | tail -1 | grep -Po "[\.\w-].*")"
      if [ -n "$(echo "$current_file" | grep " -> ")" ]; then
        current_file="$(echo "$current_file" | awk -F' -> ' '{print $1}')"
      fi

      if [ "$current_file" = "../" ] || [ "$current_file" = "./" ]; then
        echo "fail 'Cannot copy ./ or ../'"
        exit
      fi

      echo "set-option buffer _tree_copied_filepath '$kak_opt__tree_current_dir/$current_file'"
      echo "set-option buffer _tree_copied_action '$1'"
    }
    tree-redraw
  }

  define-command tree-copy -docstring 'Copy a file to be pasted later' %{
    _tree-assert-buffer
    _tree-get-copy-cut-path "copy"
    set-option buffer modelinefmt 'File copied'
  }

  define-command tree-cut -docstring 'Cut a file to be pasted later' %{
    _tree-assert-buffer
    _tree-get-copy-cut-path "cut"
    set-option buffer modelinefmt 'File cut'
  }

  define-command tree-paste -docstring 'Paste a file that was copied or cut' %{
    _tree-assert-buffer
    evaluate-commands %sh{
      [ -z "$kak_opt__tree_copied_filepath" ] && exit

      cd "$kak_opt__tree_current_dir"
      ui_tree="$(eval $kak_opt__tree_ui_cmd)"

      name="$(basename "$kak_opt__tree_copied_filepath")"

      case "$name" in
        *.*)
          extension="${name##*.}"
          base="${name%.*}"
          ;;
        *)
          extension=""
          base="$name"
          ;;
      esac

      new_name="$name"
      i=0

      while [ -e "$new_name" ]; do
        i=$((i+1))
        if [ -z "$extension" ]; then
          new_name="$base-$i"
        else
          new_name="$base-$i.$extension"
        fi
      done

      dest="$kak_opt__tree_current_dir/$new_name"

      copy() {
        local src="$1"
        local dest="$2"
        if [ -d "$src" ]; then
          cp -r "$src" "$dest"
        else
          cp "$src" "$dest"
        fi
      }

      if [ "$kak_opt__tree_copied_filepath" = "$kak_opt__tree_current_dir/" ]; then
        echo "fail 'Cannot copy/move into self'"
        exit
      fi

      if [ "$kak_opt__tree_copied_action" = "copy" ]; then
        copy "$kak_opt__tree_copied_filepath" "$dest"
      elif [ "$kak_opt__tree_copied_action" = "cut" ]; then
        mv "$kak_opt__tree_copied_filepath" "$dest"
      fi
      if [ $? -ne 0 ]; then
        echo "fail 'Failed to paste file'"
        exit
      fi
    }
    tree-clear-copy
    tree-redraw
  }

  define-command tree-clear-copy -docstring 'Clear copy selection if it exists' %{
    _tree-assert-buffer
    set-option buffer _tree_copied_filepath ''
    set-option buffer _tree_copied_action ''
    set-option buffer modelinefmt ''
    tree-redraw
  }

  define-command tree-rename -docstring 'Rename a file' %{
    _tree-assert-buffer
    evaluate-commands %sh{
      cd "$kak_opt__tree_current_dir"
      ui_tree="$(eval $kak_opt__tree_ui_cmd)"
      current_file="$(echo "$ui_tree" | head -$kak_cursor_line | tail -1 | grep -Po "[\.\w-].*")"
      if [ -n "$(echo "$current_file" | grep " -> ")" ]; then
        current_file="$(echo "$current_file" | awk -F' -> ' '{print $1}')"
      fi
      echo "set-register f '$current_file'"
    }
    evaluate-commands -save-regs 'f' %{
      prompt -init "%reg{f}" "Rename:" %{
        evaluate-commands %sh{
        cd "$kak_opt__tree_current_dir"
          mv "$kak_reg_f" "$kak_text"
          [ $? -ne 0 ] && echo "fail 'Could not rename file'"
        }
        tree-redraw
      }
    }
  }

  define-command -hidden _tree-cd-impl -params 2 %{
    evaluate-commands %sh{
      cd "$kak_opt__tree_current_dir"

      dir="$1"
      ret_dir="$2"

      echo "change-directory '$ret_dir'"

      cd "$dir"

      # Doing this as to not need to check that `$dir` is a link
      if [ $? -ne 0 ]; then
        echo "fail '`$dir` is not a directory'"
        exit
      fi

      echo "set-option buffer _tree_current_dir '$PWD'"
    }
    tree-redraw
  }

  define-command -hidden _tree-cd-prompt -params 1 %{
    prompt -on-abort 'change-directory %arg{1}' -menu -file-completion "Directory:" %{
      _tree-cd-impl "%val{text}" "%arg{1}"
    }
  }

  define-command tree-cd -docstring 'Change directory of filetree. if <directory> is provided, cd there or open prompt selection' -params ..1 %{
    _tree-assert-buffer
    evaluate-commands -save-regs 'd' %{
      set-register d %sh{pwd}
      change-directory %opt{_tree_current_dir}
      evaluate-commands %sh{
        if [ -n "$1" ]; then
          echo "_tree-cd-impl '$1' '$kak_reg_d'"
        else
          echo "_tree-cd-prompt '$kak_reg_d'"
        fi
      }
    }
  }

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

    evaluate-commands %sh{
      echo "add-highlighter -override buffer/ regex '^($kak_opt__tree_copied_indicator)' 1:red"
    }

    hook window RawKey .* %{
      _tree-hline
    }
  }

  hook global ClientClose %opt{_tree_client} %{
    tree-disable
  }
}

require-module tree
