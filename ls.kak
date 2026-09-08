provide-module ls %{
  declare-option -docstring "Dircection the ls pane is opened [left,right,up,down] (TMUX)" str ls_direction "left"
  declare-option -docstring "Size of the ls pane in percentage (TMUX)" int ls_size 20

  declare-option -hidden str _ls_current_dir "."
  declare-option -hidden str _ls_cmd \
    "printf '%%s\n' ""$(basename $PWD)/""; ls --group-directories-first -1 -A -L -p | sed -E 's|^|  |'"
  declare-option -hidden str _ls_jump_client "lsjumpclient"
  declare-option -hidden str _ls_client "lsclient"
  declare-option -hidden str-list _ls_selected_filepaths
  declare-option -hidden str _ls_selected_indicator "\+"
  declare-option -hidden str-list _ls_copied_filepaths
  declare-option -hidden str _ls_copied_action
  declare-option -hidden str _ls_copied_indicator "\*"
  declare-option -hidden str _ls_hline_face "default,default+@SecondarySelection"
  declare-option -hidden str-to-str-map _ls_dir_positions # (dir=cursor_line)
  declare-option -hidden str _ls_files_to_rename

  define-command -hidden _ls-assert-buffer %{
    evaluate-commands %sh{
      if [ ! "$kak_bufname" = "*ls*" ]; then
        echo "fail 'Not in "*ls*" buffer'"
      fi
    }
  }

  define-command -hidden -params 1 _ls-jump-client-send-cmd %{
    evaluate-commands -try-client %opt{_ls_jump_client} %arg{1}
  }
  define-command -hidden -params 1 _ls-client-send-cmd %{
    evaluate-commands -try-client %opt{_ls_client} %arg{1}
  }
  define-command -hidden _ls-hline %{
    set-face window PrimaryCursor %opt{_ls_hline_face}
    set-face window PrimaryCursorEol %opt{_ls_hline_face}
    try %{ remove-highlighter window/hlline }
    try %{ add-highlighter window/hlline line %val{cursor_line} %opt{_ls_hline_face} }
  }

  define-command -override -hidden _ls-redraw-impl -params ..1 %{
    _ls-assert-buffer
    set-option buffer readonly false
    evaluate-commands %sh{
      [ -n "$1" ] && printf '%s\n' "set-option window _ls_current_dir '$1'"
    }
    evaluate-commands -save-regs 'c' %{
      set-register c %sh{
        cd "$kak_opt__ls_current_dir" || exit

        ui="$(eval "$kak_opt__ls_cmd")"

        if [ -n "$kak_quoted_opt__ls_copied_filepaths" ]; then
          eval "set -- $kak_quoted_opt__ls_copied_filepaths"
          while [ $# -gt 0 ]; do
            path="$1"
            shift

            if [ "$kak_opt__ls_current_dir" = "$(dirname "$path")" ]; then
              path_basename="$(basename "$path")"
              case "$path" in
                */) path_basename="$path_basename/" ;;
              esac
              ui="$(printf '%s' "$ui" | sed -E "s|^.(.+$path_basename)$|$kak_opt__ls_copied_indicator\1|")"
            fi
          done
        fi

        if [ -n "$kak_quoted_opt__ls_selected_filepaths" ]; then
          eval "set -- $kak_quoted_opt__ls_selected_filepaths"
          while [ $# -gt 0 ]; do
            path="$1"
            shift

            if [ "$kak_opt__ls_current_dir" = "$(dirname "$path")" ]; then
              path_basename="$(basename "$path")"
              case "$path" in
                */) path_basename="$path_basename/" ;;
              esac
              ui="$(printf '%s' "$ui" | sed -E "s|^.(.+$path_basename)$|$kak_opt__ls_selected_indicator\1|")"
            fi
          done
        fi
        printf '%s\n' "$ui"
      }

      execute-keys '%"cRgg'
      set-option buffer readonly true
    }

    # Jump cursor to last known position in directory
    evaluate-commands %sh{
      eval "set -- $kak_quoted_opt__ls_dir_positions"
      while [ $# -gt 0 ]; do
        pos="$1"
        shift

        dir="$(printf '%s' "$pos" | sed -E 's|=.+||; s|^\s+||; s|\s+$||')"
        line="$(printf '%s' "$pos" | sed 's|.*=||')"
        if [ "$dir" = "$kak_opt__ls_current_dir" ]; then
          printf '%s\n' "execute-keys '${line}ggh'"
          exit
        fi
      done
    }
    _ls-hline
  }

  define-command ls-redraw -docstring 'Redraw the filebrowser' %{
    _ls-redraw-impl
  }

  define-command -hidden _ls-enable-impl -params 1 %{
      edit -debug -scratch "*ls*"
      set-option window filetype ls
      rename-client "%opt{_ls_client}"
      execute-keys "gg"
      _ls-redraw-impl %arg{1}
  }

  define-command ls-enable -docstring 'Open the filebrowser' %{
    try %{
      ls-disable
    }
    set-option global _ls_jump_client "%val{client}"
    evaluate-commands %sh{
      dir=
      [ -f "$kak_buffile" ] && dir="$(dirname "$kak_buffile")" || dir="$PWD"
      get_direction_flags() {
        case "$1" in
          "up")    printf '%s\n' "-v -b" ;;
          "down")  printf '%s\n' "-v"    ;;
          "left")  printf '%s\n' "-h -b" ;;
          "right") printf '%s\n' "-h"    ;;
        esac
      }

      if [ -n "$TMUX" ]; then
        flags="$(get_direction_flags "$kak_opt_ls_direction")"
        if [ -z "$flags" ]; then
          printf "fail 'Invalid direction: %s'\n" "$direction"
          exit
        fi
        #shellcheck disable=SC2086
        tmux split-window -l "$kak_opt_ls_size%" $flags "kak -c $kak_session -e '_ls-enable-impl %{$dir}'" > /dev/null
      else
        echo "new '_ls-enable-impl %{$dir}'"
      fi
    }
  }

  define-command ls-disable -docstring 'Close the filebrowser' %{
    try %{ delete-buffer "*ls*" } catch %{ fail }
    try %{ evaluate-commands -client %opt{_ls_client} quit }
  }

  define-command ls-toggle -docstring 'Toggle visibility of filebrowser' %{
    try %{
      ls-disable
    } catch %{
      ls-enable
    }
  }

  define-command ls-open -docstring 'Open a file' %{
    _ls-assert-buffer
    evaluate-commands %sh{
      open(){
        filepath="$1"

        if [ -d "$filepath" ]; then
          cd "$filepath" || exit
          echo "set-option window _ls_current_dir \"$PWD\""
        elif [ -f "$filepath" ]; then
          filepath="$(printf '%s' "$kak_opt__ls_current_dir/$filepath" | sed 's|\ |\\ |g')"

          if echo "$kak_client_list" | grep -qo "$kak_opt__ls_jump_client"; then
            echo "evaluate-commands -client $kak_opt__ls_jump_client %{ edit -existing %{$filepath} }" | kak -p "$kak_session"
            if [ -n "$TMUX" ]; then
              echo "focus $kak_opt__ls_jump_client"
            fi
          else
            cmd="kak -c $kak_session -e 'edit -existing %{$filepath}; rename-client %{$kak_opt__ls_jump_client}'"
            if [ -n "$TMUX" ]; then
              tmux split-window -c "$dir" -l "80%" -h "$cmd" > /dev/null
            elif [ -n "$kak_opt_termcmd" ]; then
              $kak_opt_termcmd "cd $dir; $cmd"
            elif [ -n "$TERMINAL" ]; then
              $TERMINAL -e sh -c "cd $dir; $cmd" || $TERMINAL -x sh -c "cd $dir; $cmd" || $TERMINAL sh -c "cd $dir; $cmd"
            else
              printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}No defined way  to open file, see *debug* buffer'}"
              printf 'fail\n'
            fi
          fi
        fi
      }

      cd "$kak_opt__ls_current_dir" || exit
      ui="$(eval "$kak_opt__ls_cmd")"
      current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

      open "$current_file"
    }
    ls-redraw
  }

  define-command ls-create -docstring 'Create a file' %{
    _ls-assert-buffer
    evaluate-commands %{
      prompt "Create:" %{
        evaluate-commands %sh{
          cd "$kak_opt__ls_current_dir" || exit
          if printf '%s' "$kak_text" | grep -q '.*/$'; then
            mkdir -p "$kak_text"
          else
            DIR_PATH=$(dirname "$kak_text")
            mkdir -p "$DIR_PATH"
            touch "$kak_text"
          fi
        }
        ls-redraw
      }
    }
  }

  define-command ls-delete -docstring 'Delete a file' %{
    _ls-assert-buffer
    prompt %sh{
      eval "set -- $kak_quoted_opt__ls_selected_filepaths"
      count="$#"
      [ $count -eq 0 ] && count=1
      files="$([ $count -gt 1 ] && echo 'files' || echo 'file')"
      printf "Delete %s? [y/n]:" "$count $files"
    } \
    %{
      evaluate-commands %sh{
        if [ ! "$kak_text" = "y" ] && [ ! "$kak_text" = "Y" ]; then
          exit
        fi

        remove_file() {
          if [ -x "$(command -v trash-put)" ]; then
            trash-put "$1"
          else
            rm -rf "$1"
          fi
        }

        if [ -n "$kak_quoted_opt__ls_selected_filepaths" ]; then
          eval "set -- $kak_quoted_opt__ls_selected_filepaths"
          while [ $# -gt 0 ]; do
            path="$1"
            shift

            remove_file "$path"
          done
        else
          cd "$kak_opt__ls_current_dir" || exit
          ui="$(eval "$kak_opt__ls_cmd")"

          current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

          if [ "$kak_cursor_line" -eq 1 ]; then
            printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Can not delete $kak_opt__ls_current_dir/'}"
            printf 'fail\n'
            exit
          fi

          remove_file "$kak_opt__ls_current_dir/$current_file"
        fi
      }
      ls-clear
      ls-redraw
    }
  }

  define-command ls-toggle-select %{
    _ls-assert-buffer
    evaluate-commands -itersel %{
      evaluate-commands %sh{
        cd "$kak_opt__ls_current_dir" || exit
        ui="$(eval "$kak_opt__ls_cmd")"
        current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

        if [ "$kak_cursor_line" -eq 1 ]; then
          printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Can not select $kak_opt__ls_current_dir/'}"
          printf 'fail\n'
          exit
        fi

        current_file="$kak_opt__ls_current_dir/$current_file"

        eval "set -- $kak_quoted_opt__ls_selected_filepaths"
        count=$#
        found=false
        while [ $# -gt 0 ]; do
          path="$1"
          shift

          if [ "$path" = "$current_file" ]; then
            printf '%s\n' "set-option -remove window _ls_selected_filepaths '$path'"
            count=$((count - 1))
            found=true
            break
          fi
        done

        if [ $found = false ]; then
          printf '%s\n' "set-option -add window _ls_selected_filepaths '$current_file'"
          extra_path="$current_file"
          count=$((count + 1))
        fi

        if [ $count -gt 0 ]; then
          printf '%s\n' "_ls-jump-client-send-cmd %{info -title '$count selected' %{$(
            eval "set -- $kak_quoted_opt__ls_selected_filepaths"
            while [ $# -gt 0 ]; do
              path="$1"
              shift

              if [ "$path" = "$current_file" ]; then
                continue
              fi
              printf '%s\n' "$path"
            done
            if [ -n "$extra_path" ]; then
              printf '%s\n' "$extra_path"
            fi
          )}}"
        else
          printf '%s\n' "_ls-jump-client-send-cmd %{execute-keys <esc>}"
        fi
      }
    }
    ls-redraw
  }

  define-command -hidden _ls-get-copy-cut-path -params 1 %{
    evaluate-commands %sh{
      action="$1"
      cd "$kak_opt__ls_current_dir" || exit
      ui="$(eval "$kak_opt__ls_cmd")"
      current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

      if [ "$kak_cursor_line" -eq 1 ]; then
        printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Can not copy $kak_opt__ls_current_dir/'}"
        printf 'fail\n'
        exit
      fi

      printf '%s\n' "set-option window _ls_copied_filepaths"
      if [ -n "$kak_quoted_opt__ls_selected_filepaths" ]; then
        eval "set -- $kak_quoted_opt__ls_selected_filepaths"
        while [ $# -gt 0 ]; do
          path="$1"
          shift

          printf '%s\n' "set-option -add window _ls_copied_filepaths '$path'"
        done
        printf '%s\n' "set-option window _ls_selected_filepaths"
      else
        printf '%s\n' "set-option -add window _ls_copied_filepaths '$kak_opt__ls_current_dir/${current_file}'"
      fi
      printf '%s\n' "set-option window _ls_copied_action '$action'"
    }
    ls-redraw
  }

  define-command ls-copy -docstring 'Copy a file to be pasted later' %{
    _ls-assert-buffer
    _ls-get-copy-cut-path "copy"
    evaluate-commands %sh{
      eval "set -- $kak_quoted_opt__ls_copied_filepaths"
      count="$#"
      if [ $count -eq 0 ]; then
        count=1
        eval "set -- '$kak_opt__ls_current_dir/${current_file}'"
      fi
      printf '%s\n' "_ls-jump-client-send-cmd %{info -title '$count copied' %{$(while [ $# -gt 0 ]; do
        printf '%s\n' "$1"
        shift
      done)}}"
    }
  }

  define-command ls-cut -docstring 'Cut a file to be pasted later' %{
    _ls-assert-buffer
    _ls-get-copy-cut-path "cut"
    evaluate-commands %sh{
      eval "set -- $kak_quoted_opt__ls_copied_filepaths"
      count="$#"
      if [ $count -eq 0 ]; then
        count=1
        eval "set -- '$kak_opt__ls_current_dir/${current_file}'"
      fi
      printf '%s\n' "_ls-jump-client-send-cmd %{info -title '$count cut' %{$(while [ $# -gt 0 ]; do
        printf '%s\n' "$1"
        shift
      done)}}"
    }
  }

  define-command ls-paste -docstring 'Paste a file that was copied or cut' %{
    _ls-assert-buffer
    evaluate-commands %sh{
      [ -z "$kak_opt__ls_copied_filepaths" ] && exit

      cd "$kak_opt__ls_current_dir" || exit

      copy() {
        src="$1"
        dest="$2"
        if [ -d "$src" ]; then
          cp -r "$src" "$dest"
        else
          cp "$src" "$dest"
        fi
      }

      eval "set -- $kak_quoted_opt__ls_copied_filepaths"
      while [ $# -gt 0 ]; do
        path="$1"
        shift

        name="$(basename "$path")"

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

        dest="$kak_opt__ls_current_dir/$new_name"

        if [ "$path" = "$kak_opt__ls_current_dir/" ]; then
          printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Can not copy or move into self'}"
          printf 'fail\n'
          exit
        fi

        if [ "$kak_opt__ls_copied_action" = "copy" ]; then
          copy "$path" "$dest"
        elif [ "$kak_opt__ls_copied_action" = "cut" ]; then
          mv "$path" "$dest"
        fi
        #shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
          printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Failed to paste file, see *debug* buffer'}"
          printf 'fail\n'
          exit
        fi
      done
    }
    ls-clear
    ls-redraw
  }

  define-command ls-clear -docstring 'Clear selections if they exist' %{
    _ls-assert-buffer
    set-option window _ls_selected_filepaths
    set-option window _ls_copied_filepaths
    set-option window _ls_copied_action ''
    _ls-jump-client-send-cmd %{execute-keys <esc>}
    ls-redraw
  }

  define-command ls-rename -docstring 'Rename a file' %{
    _ls-assert-buffer
    evaluate-commands %sh{
      cd "$kak_opt__ls_current_dir" || exit
      ui="$(eval "$kak_opt__ls_cmd")"
      current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

      if [ "$kak_cursor_line" -eq 1 ]; then
        printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Can not rename $kak_opt__ls_current_dir'}"
        printf 'fail\n'
        exit
      fi
      echo "set-register f '$current_file'"
    }
    evaluate-commands -save-regs 'f' %{
      prompt -init "%reg{f}" "Rename:" %{
        evaluate-commands %sh{
        cd "$kak_opt__ls_current_dir" || exit
          if ! mv "$kak_reg_f" "$kak_text"; then
            printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Could not rename file, see *debug* buffer'}"
            printf 'fail\n'
          fi
        }
        ls-redraw
      }
    }
  }
  define-command ls-rename-in-editor -docstring 'Rename selected files in editor' %{

    evaluate-commands -save-regs 'f' %{
      set-register f %sh{
        if [ -n "$kak_quoted_opt__ls_selected_filepaths" ]; then
          eval "set -- $kak_quoted_opt__ls_selected_filepaths"
          while [ $# -gt 0 ]; do
            printf '%s' "$1///"
            shift
          done
        else
          cd "$kak_opt__ls_current_dir" || exit
          ui="$(eval "$kak_opt__ls_cmd")"
          current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"
          printf '%s' "$kak_opt__ls_current_dir/$current_file///"
        fi
      }

      _ls-jump-client-send-cmd "edit -scratch '*ls-rename*'"
      _ls-jump-client-send-cmd %{execute-keys '"fRs///<ret>c<ret><esc>gex<a-d>%'}
      _ls-jump-client-send-cmd %{execute-keys '"fy'}
      _ls-jump-client-send-cmd %{set-option window _ls_files_to_rename %sh{ printf '%s' "$kak_reg_f" }}
      _ls-jump-client-send-cmd "execute-keys 'gg'"
      focus %opt{_ls_jump_client}
    }
  }

  define-command ls-rename-in-editor-write -docstring 'Finalize renamed files' %{
    evaluate-commands %sh{
      if [ ! "$kak_bufname" = "*ls-rename*" ]; then
        printf '%s\n' "fail 'Not in "*ls-rename*" buffer'"
      fi
    }
    evaluate-commands %{
      execute-keys '%_'
      evaluate-commands %sh{
        index="$kak_opt__ls_files_to_rename"
        index_edit="$kak_selection"
        failed_rename=false
        #shellcheck disable=SC2046
        if [ $(printf '%s' "$index" | wc -l) -eq $(printf '%s' "$index_edit" | wc -l) ]; then
          max=$(($(printf '%s' "$index" | wc -l)+1))
          counter=1
          while [ $counter -le $max ]; do
            a="$(printf '%s' "$index" | sed "${counter}q;d")"
            b="$(printf '%s' "$index_edit" | sed "${counter}q;d")"
            counter=$((counter + 1))

            [ "$a" = "$b" ] && continue
            if [ -e "$b" ]; then
              failed_rename=true
              printf "echo -debug 'Failed to rename %s as %s already exists'\n" "$a" "$b"
              continue
            fi
            mv "$a" "$b"
          done
        else
          printf '%s\n' "fail 'ERROR: Number of lines don't match selected files'"
        fi
        if [ "$failed_rename" = true ]; then
          printf '%s\n' "echo -markup '{Error}Failed to rename some files, see *debug* buffer'"
        fi
      }
    }
    delete-buffer "*ls-rename*"
    focus %opt{_ls_client}
    _ls-client-send-cmd "ls-clear"
    _ls-client-send-cmd "ls-redraw"
  }

  define-command -hidden _ls-cd-impl -params 2 %{
    evaluate-commands %sh{
      cd "$kak_opt__ls_current_dir" || exit

      dir="$1"
      dir="$(printf '%s' "$dir" | sed "s|^~|$HOME|")"

      ret_dir="$2"

      echo "change-directory '$ret_dir'"

      # Doing this as to not need to check that `$dir` is a link
      if ! cd "$dir"; then
        printf '%s\n' "_ls-jump-client-send-cmd %{echo -markup '{Error}Failed to change directory, see *debug* buffer'}"
        printf 'fail\n'
        exit
      fi

      echo "set-option window _ls_current_dir '$PWD'"
    }
    ls-redraw
  }

  define-command ls-cd -params 1 \
  -docstring 'ls-cd: <directory>: Change directory of filebrowser to <directory>' \
  %{
    _ls-assert-buffer
    evaluate-commands -save-regs 'd' %{
      set-register d %sh{pwd}
      change-directory %opt{_ls_current_dir}
      _ls-cd-impl %arg{1} %reg{d}
    }
  }
  complete-command -menu ls-cd shell-script %{
    cd "$kak_opt__ls_current_dir"
    input="$1"
    if [ -z "$input" ]; then
      ls -1 -a -p -L "." | grep "/$"
    elif [ -z "${input%/*}" ]; then
      ls -1 -A -p -L "/" | grep "/$" | (echo "/"; xargs -I {} echo '/{}') | grep "$input"
    elif [ -d "$input" ]; then
      input="${input%/}" # remove it to add it back later as it is not always present
      echo "$input/"
      ls -1 -A -p -L "$input" | grep "/$" | xargs -I {} echo "$input/{}"
    elif [ ! "${input%/*}" = "$input" ]; then
      ls -1 -A -p -L "${input%/*}" | grep "/$" | xargs -I {} echo "${input%/*}/{}" | grep "$input"
    fi
  }


  define-command ls-run -params .. \
  -docstring 'ls-run [<command>]: Run <command> in current ls directory. if <command> is provided, run it or open prompt' \
  %{
    _ls-assert-buffer
    evaluate-commands -save-regs 'd' %{
      set-register d %sh{pwd}
      change-directory %opt{_ls_current_dir}
      evaluate-commands %sh{
        if [ -n "$1" ]; then
          "$@" > /dev/null
          printf 'change-directory "%s"\n' "$kak_reg_d"
          printf "ls-redraw\n"
        else
        #shellcheck disable=SC2016
          printf 'prompt -shell-completion "Command:" %%{
            nop %%sh{
              eval "$kak_text"
            }
            change-directory "%s"
            ls-redraw
          }\n' "$kak_reg_d"
        fi
      }
    }
  }

  define-command ls-copy-path %{
    evaluate-commands %sh{
      cd "$kak_opt__ls_current_dir" || exit
      ui="$(eval "$kak_opt__ls_cmd")"
      current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

      echo "set-register dquote '$kak_opt__ls_current_dir/$current_file'"
    }
  }

  define-command ls-copy-name %{
    evaluate-commands %sh{
      cd "$kak_opt__ls_current_dir" || exit
      ui="$(eval "$kak_opt__ls_cmd")"
      current_file="$(echo "$ui" | head -"$kak_cursor_line" | tail -1 | grep -o '[.[:alnum:]_-].*')"

      echo "set-register dquote '$current_file'"
    }
  }

  define-command ls-copy-directory %{
    evaluate-commands %sh{
      echo "set-register dquote '$kak_opt__ls_current_dir'"
    }
  }

  hook global WinSetOption filetype=ls %{
    set-option window modelinefmt ''

    evaluate-commands %sh{
      printf '%s\n' "add-highlighter -override window/ls_directory regex '[^\n]+/' 0:link"
      printf '%s\n' "add-highlighter -override window/ls_copied_indicator regex '^($kak_opt__ls_copied_indicator)' 1:red"
      printf '%s\n' "add-highlighter -override window/ls_selected_indicator regex '^($kak_opt__ls_selected_indicator)' 1:cyan"
    }

    hook window RawKey .* %{
      _ls-hline

      evaluate-commands %sh{
        printf '%s\n' "set-option -add window _ls_dir_positions '$kak_opt__ls_current_dir=$kak_cursor_line'"
      }
    }
  }

  hook global ClientClose %opt{_ls_client} %{
    try %{ ls-disable }
  }
}

require-module ls
