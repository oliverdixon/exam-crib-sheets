#!/bin/bash
# OWD 2023

# This script requires a moderately recent version of GhostScript (10+, for the
# new C-based PDF parser) and a copy of ImageMagick with the PDF and PNG codecs
# installed and enabled.

GIT_ROOT="$(git rev-parse --show-toplevel)"
INDEX="$GIT_ROOT/publishing_index"
remote_list=()

print_warning () {
        echo -e "$(basename "$0"): Warning: $@" >&2
}

print_info () {
        echo -e "$(basename "$0"): Info: $@"
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
                print_info "Compressed: $1 from $(du -h "$1" | cut -f1) to" \
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
                [[ $ret -eq 0 ]] && print_info "Rasterised: $1"
        fi

        return $ret
}

# upload_files: Given a list of files, determine the most efficient route to
# transport them to the predefined host. If we are already on a York machine, we
# can do a local copy with rsync. Otherwise, rsync-over-SSH is used.

upload_files () {
        local WEB_PATH="~/web/exam-crib-sheets"
        local SSH_URL="maxwell.york.ac.uk"
        local NET_DOMAIN="its.york.ac.uk"
        local NET_USER="od641"

        if [[ "$#" -le 1 ]]; then
                print_warning "Nothing to process or upload!"
                return 0
        fi

        if [[ $(dnsdomainname) == $NET_DOMAIN ]] && \
                        [[ $(whoami) == $NET_USER ]]; then
                print_info "Copying to the Local Network..."
                rsync -Rvtu "$@" "${WEB_PATH/#\~/$HOME}"
        else

                print_info "Publishing to the Remote... (Requires York network" \
                        "access)"
                rsync -Rvtu -e 'ssh -q' "$@" "$NET_USER@$SSH_URL:$WEB_PATH"
        fi

        return $?
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
                        if [[ $? -ne 0 ]]; then
                                print_warning "Skipping processing of $file"
                                continue
                        fi
                fi

                remote_list+=("$remote_file")

                # Re-generate rasters for the given file, where necessary.
                update_raster "$file"

                if [[ $? -eq 0 ]]; then
                        # Update the remote publication list, assuming that two
                        # raster pages were generated for each file.
                        remote_List+="${remote_file%.*}_Raster-0.png" \
                                "${remote_file%.*}_Raster-1.png"
                else
                        print_warning "Skipping rasters of $file"
                fi
        else
                print_warning "$file was listed in the index but does not" \
                        "exist."
        fi
done < "$INDEX"

# Send all files specified by the remote list to the destination
upload_files "${remote_list[@]}"

exit $?

