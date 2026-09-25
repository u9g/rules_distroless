#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

readonly bsdtar="$1"
readonly yq="$2"
readonly awk="$3"
readonly coreutils="$4"
readonly base="$5"
readonly path="${6#/}"
readonly lines="$7"
readonly out="$8"

tmp=$("$coreutils" mktemp -d)
trap '"$coreutils" rm -rf "$tmp"' EXIT

# The base's layers, the newest first: those an OCI image layout's manifest
# names, or the base itself if it is a tar.
layers=()
if [[ -d "$base" ]]; then
    json() {
        "$yq" -p json -o yaml "$@"
    }
    blob() {
        echo "$base/blobs/${1%%:*}/${1#*:}"
    }
    if [[ "$(json '.manifests | length' "$base/index.json")" != "1" ]]; then
        echo "ERROR: $base/index.json does not name exactly one image" >&2
        exit 1
    fi
    manifest=$(blob "$(json '.manifests[0].digest' "$base/index.json")")
    if [[ "$(json 'has("manifests")' "$manifest")" == "true" ]]; then
        echo "ERROR: $base is an image index for several platforms; use the image for one of them" >&2
        exit 1
    fi
    while read -r digest; do
        layers=("$(blob "$digest")" ${layers[@]+"${layers[@]}"})
    done < <(json '.layers[].digest' "$manifest")
else
    layers=("$base")
fi

# The file as the newest layer that has it has it, unless a layer above that
# one deleted it with a whiteout.
# https://github.com/opencontainers/image-spec/blob/main/layer.md#whiteouts
readonly dir="${path%/*}"
readonly whiteout="$dir/.wh.${path##*/}"
readonly opaque="$dir/.wh..wh..opq"
found=""
for layer in ${layers[@]+"${layers[@]}"}; do
    has=$("$bsdtar" -tf "$layer" | "$awk" -v path="$path" -v whiteout="$whiteout" -v opaque="$opaque" '
        { sub(/^\.\//, "") }
        $0 == path { has = "file" }
        ($0 == whiteout || $0 == opaque) && has == "" { has = "whiteout" }
        END { print has }
    ')
    if [[ "$has" == "file" ]]; then
        "$bsdtar" -xf "$layer" -C "$tmp" "$path"
        found="$tmp/$path"
        break
    elif [[ "$has" == "whiteout" ]]; then
        break
    fi
done

if [[ -z "$found" ]]; then
    echo "ERROR: $base has no /$path to add to" >&2
    exit 1
fi

# The base's file, then the lines, which must not name an entry it has. awk
# ends the base's last line with a newline if it had none.
"$awk" -F: -v path="/$path" '
    FILENAME == ARGV[1] { names[$1] = 1; print; next }
    $1 in names {
        printf("ERROR: %s already has an entry for %s\n", path, $1) > "/dev/stderr"
        exit 1
    }
    { print }
' "$found" "$lines" >"$out"
