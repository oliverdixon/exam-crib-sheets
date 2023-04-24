#!/bin/bash
# OWD 2023

SSH_URL="od641@maxwell.york.ac.uk:~/web/exam-crib-sheets/"
GIT_ROOT="$(git rev-parse --show-toplevel)"
INDEX="$GIT_ROOT/publishing-index"
publish_list=()

# compress_pdf: Given a single PDF file, use GhostScript to perform an in-place
# compression, and report the compression ratio to stdout. The GS return code is
# forwarded.

compress_pdf () {
        local TMP_NAME="$(dirname "$1")/tmp-$(date '+%s')-$RANDOM.pdf"
        local PRINT_NAME="$(realpath --relative-to=./ "$1")"

        gs                               \
                -sDEVICE=pdfwrite        \
                -dCompatibilityLevel=1.5 \
                -dNOPAUSE                \
                -dQUIET                  \
                -dBATCH                  \
                -dPrinted=false          \
                -sOutputFile="$TMP_NAME" "$1"

        local ret=$?

        if [[ $ret -eq 0 ]]; then
                echo -e "$PRINT_NAME\t$(du -h "$1" | cut -f1) ->" \
                        "$(du -h --apparent-size "$TMP_NAME" | cut -f1)"
                mv "$TMP_NAME" "$1"
        fi

        return $ret
}

# We first compress each file listed in the index that does not have a
# GhostScript invocation marker. GREP is well-defined to return '1' when the
# file was successfully opened, but no matching lines were found. If GS is
# required, but did not execute successfully, then its return code is forwarded.

echo "Processing Uncompressed Files..."
while read file; do
        file="$GIT_ROOT/${file}"

        if [[ -f "$file" ]]; then
                publish_list+=("$file")
                grep -qs "%%Invocation: gs" "$file"

                if [ $? -eq 1 ]; then
                        compress_pdf "$file"
                        ret=$?
                        [ $ret -ne 0 ] && exit $ret
                fi
        fi
done < "$INDEX"

# If necessary, send all valid files listed by the publication index to the
# remote with rsync, where the local copy is newer. The rsync return code is
# forwarded.

if [ ${#publish_list[@]} -ne 0 ]; then
        echo -e "\nPublishing to the Remote... (Requires York VPN access)"
        rsync -vtu --ignore-missing-args "${publish_list[@]}" "$SSH_URL"
        ret=$?
else
        echo -e "\nNothing to do!"
        ret=0
fi

exit $ret

