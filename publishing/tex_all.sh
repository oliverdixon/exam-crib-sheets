#!/bin/bash
# OWD 2023

# This script will invoke Latexmk on every file enumerated in the publication
# index. By default, TeX will be instructed to compile the sources to a complete
# PDF, however any arguments supplied to this script will override the '-pdf'
# option. This program will pass through the final non-zero exit code of
# Latexmk, or zero if all invocations completed successfully.

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
[[ $# -gt 0 ]] && LATEXMK_ARGS="$@" || LATEXMK_ARGS="-pdf"

while read line; do
        [[ -z $line ]] || [[ $line == \#* ]] && continue

        file="$(realpath --relative-to=./ "$GIT_ROOT/$line")"

        print_info "TeX'ing $file with $LATEXMK_ARGS"
        latexmk -cd "$LATEXMK_ARGS" ${file%.*}
        tmpret=$?

        if [[ $tmpret -ne 0 ]]; then
                ret=$tmpret
                print_warning "Latexmk returned a non-zero exit code for" \
                        "$file"
        fi

done < "$INDEX"

[[ $ret -ne 0 ]] && print_warning "Some invocations of Latexmk returned a" \
        "non-zero exit code"
exit $ret

