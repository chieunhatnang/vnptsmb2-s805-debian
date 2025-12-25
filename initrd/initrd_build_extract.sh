#!/bin/bash
set -e

# Strict limit in bytes
LIMIT_BYTES=$((0x20f1df))
BASEDIR="./"

CMD="${1:-build}"

cd "$BASEDIR"

case "$CMD" in
  extract)
    rm -rf uinitrd_trimmed
    mkdir -p uinitrd_trimmed
    chmod 777 uinitrd_trimmed
    cd uinitrd_trimmed
    dd if=../uInitrd_big_orig bs=64 skip=1 | gzip -dc | cpio -idmv
    chmod 777 ./*
    ;;

  build)
    if [ ! -d uinitrd_trimmed ]; then
      echo "ERROR: uinitrd_trimmed directory does not exist. Run '$0 extract' first." >&2
      exit 1
    fi

    rm -f uinitrd_tiny
    cd uinitrd_trimmed
    find . | cpio -o -H newc | gzip -9 > ../uinitrd_tiny
    cd ..

    ls -l uinitrd_tiny

    SIZE_BYTES="$(stat -c%s uinitrd_tiny)"
    DIFF_BYTES=$((LIMIT_BYTES - SIZE_BYTES))

    printf 'Initrd size   : %d bytes (0x%X)\n' "$SIZE_BYTES" "$SIZE_BYTES"
    printf 'Size limit    : %d bytes (0x%X)\n' "$LIMIT_BYTES" "$LIMIT_BYTES"
    printf 'Limit - size  : %d bytes (0x%X)\n' "$DIFF_BYTES" "$DIFF_BYTES"

    if [ "$SIZE_BYTES" -gt "$LIMIT_BYTES" ]; then
        echo "ERROR: uinitrd_tiny is BIGGER than the 0x20f1df limit!" >&2
        exit 1
    else
        echo "OK: uinitrd_tiny fits within the 0x20f1df limit."
    fi
    ;;

  *)
    echo "Usage: $0 [build|extract]" >&2
    exit 1
    ;;
esac

