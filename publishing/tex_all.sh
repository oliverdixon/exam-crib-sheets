#!/bin/bash
# OWD 2023

GIT_ROOT="$(git rev-parse --show-toplevel)"
INDEX="$GIT_ROOT/publishing/index"
PROG_NAME="$(basename "$0")"

print_warning () {
        echo -e "$PROG_NAME: Warning: $@" >&2
}

print_info () {
        echo -e "$PROG_NAME: Info: $@"
}

ret=0

while read line; do
        [[ -z $line ]] || [[ $line == \#* ]] && continue

        file="$(realpath --relative-to=./ "$GIT_ROOT/$line")"

        print_info "TeX'ing $file"
        latexmk -cd -pdf ${file%.*}

        ret=$?
        [[ $ret -ne 0 ]] && print_warning "latexmk returned a non-zero code" \
                "for $file"
done < "$INDEX"

[[ $ret -ne 0 ]] && print_warning "Some files failed to correctly compile"
exit $ret

