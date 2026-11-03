#!/bin/sh
# SPDX-License-Identifier: MIT
# Run on a writable repository copy with a publisher-owned private RSA key.
set -eu
[ "$#" -eq 2 ] || { echo 'usage: sign-repository REPOSITORY PRIVATE-KEY' >&2; exit 2; }
repository=$1
key=$2
case "$key" in /*) ;; *) key="$PWD/$key" ;; esac
for directory in "$repository"/*; do
    [ -d "$directory" ] || continue
    for package in "$directory"/*.apk; do
        abuild-sign -k "$key" "$package"
    done
done
for directory in "$repository"/*; do
    [ -d "$directory" ] || continue
    apk index --allow-untrusted -o "$directory/APKINDEX.tar.gz" "$repository"/*/*.apk
    abuild-sign -k "$key" "$directory/APKINDEX.tar.gz"
done
