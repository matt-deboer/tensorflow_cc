#!/bin/bash
set -e
# This file recursively traverses a directory and replaces each
# link by a copy of its target.

# To properly handle whitespace characters in filenames, we need to use
# an ugly `find` and `read` trick.
if [[ "$(uname -s)" == "Darwin" ]]; then
    find . -type l | while read -r link; do
        target=$(readlink "$link")
        if [ -e "$target" ]
        then
            rm "$link" && cp -r "$target" "$link" || echo "ERROR: Unable to change $link to $target"
        else
            echo "ERROR: Broken symlink: $link"
        fi
    done
else
    find -L "$1" -print0 |
        while IFS= read -r -d $'\0' f; do
            # We need to check whether the file is still a link.
            # It may have happened that we have already replaced it by
            # the original when some of its parent directories were copied.
            # Also the first check is to detect whether the file (after
            # symlink dereference) exists so that `realpath` does not fail.
            if [[ -e "$f" ]] && [[ -L "$f" ]]; then
                realf="$(realpath "$f")"
                rm -f "$f"
                cp -r "$realf" "$f"
            fi
        done
fi
