#!/bin/bash
# OWD 2023

# This script requires a moderately recent version of GhostScript (10+, for the
# new C-based PDF parser) and a copy of ImageMagick with the PDF and PNG codecs
# installed and enabled.

SSH_URL="od641@maxwell.york.ac.uk:~/web/exam-crib-sheets/"
GIT_ROOT="$(git rev-parse --show-toplevel)"
INDEX="$GIT_ROOT/publishing_index"
remote_list=()

print_warning () {
        echo "Warning: $@" >&2
}

# compress_pdf: Given a single PDF file, use GhostScript to perform an in-place
# compression, and report the compression ratio to stdout. The GS return code is
# forwarded.

compress_pdf () {
        local TMP_NAME="$(dirname "$1")/tmp-$(date '+%s')-$RANDOM.pdf"
        local ret=0

        gs                               \
                -sDEVICE=pdfwrite        \
                -dCompatibilityLevel=1.5 \
                -dNOPAUSE                \
                -dQUIET                  \
                -dBATCH                  \
                -dPrinted=false          \
                -sOutputFile="$TMP_NAME" \
                "$1"

        ret=$?

        if [[ $ret -eq 0 ]]; then
                echo -e "Compressed: $1 from $(du -h "$1" | cut -f1) to" \
                        "$(du -h --apparent-size "$TMP_NAME" | cut -f1)"
                mv "$TMP_NAME" "$1"
        fi

        return $ret
}

# update_raster: If the source PDF is newer than its corresponding raster, use
# ImageMagick to regenerate the PNG, and report the change. If a raster is
# out-of-date, and ImageMagick fails, its non-zero error code is forwarded.
# Otherwise, zero is returned.

update_raster () {
        local RASTER_NAME="${1%.*}_Raster"
        local ret=0

        # We only check the last-modified date of the first image page, since
        # the entire cluster would've been generated together.

        if [[ ${RASTER_NAME}-0.png -ot $1 ]]; then
                convert                   \
                        -density 150      \
                        -background white \
                        -alpha remove     \
                        -colorspace gray  \
                        -depth 4          \
                        "$1"              \
                        "${RASTER_NAME}.png"

                ret=$?
                [[ $ret -eq 0 ]] && echo "Rasterised: $1"
        fi

        return $ret
}

while read file; do
        [[ -z $file ]] || [[ $file == \#* ]] && continue

        remote_file="$GIT_ROOT/./$file"
        file="$(realpath --relative-to=./ "$GIT_ROOT/$file")"

        if [[ -f $file ]]; then
                # We first compress each file listed in the index that does not
                # have a GhostScript invocation marker. GREP is well-defined to
                # return '1' when the file was successfully opened, but no
                # matching lines were found. If GS is required, but did not
                # execute successfully, then its return code is forwarded.

                grep -qsm 1 "^%%Invocation: gs" "$file"
                if [[ $? -eq 1 ]]; then
                        compress_pdf "$file"
                        ret=$?
                        [[ $ret -ne 0 ]] && exit $ret
                fi

                # Re-generate rasters for the given file, where necessary.

                update_raster "$file"
                ret=$?
                [[ $ret -ne 0 ]] && exit $ret

                # Update the remote publication list, assuming that two raster
                # pages were generated for each file.

                remote_list+=("$remote_file" "${remote_file%.*}_Raster-0.png" \
                        "${remote_file%.*}_Raster-1.png")
        else
                print_warning "$file was listed in the index but does not" \
                        "exist."
        fi
done < "$INDEX"

# If necessary, send all valid files listed by the publication index to the
# remote with rsync, where the local copy is newer. The rsync return code is
# forwarded.

if [[ ${#remote_list[@]} -gt 0 ]]; then
        echo -e "Publishing to the Remote... (Requires York VPN access)\n"
        rsync -Rvtu --ignore-missing-args -e 'ssh -q' "${remote_list[@]}" \
                "$SSH_URL"
        ret=$?
else
        print_warning "Nothing to process or upload!"
        ret=0
fi

exit $ret

