#!/bin/sh
# OWD 2023

pandoc                     \
        -f markdown        \
        -t pdf             \
        -V colorlinks=true \
        -V allcolors=blue  \
        < "$1" | zathura -

