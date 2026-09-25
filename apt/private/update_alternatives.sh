#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

readonly bsdtar="$1"
readonly out="$2"
readonly awk="$3"
readonly coreutils="$4"
readonly mergedusr="$5"
shift 5

tmp=$("$coreutils" mktemp -d)
trap '"$coreutils" rm -rf "$tmp"' EXIT

# The multiarch tuple of a Debian architecture, for postinst scripts that spell
# their paths with $(dpkg-architecture -qDEB_HOST_MULTIARCH).
# https://wiki.debian.org/Multiarch/Tuples
triplet() {
    case "$1" in
    amd64) echo "x86_64-linux-gnu" ;;
    arm64) echo "aarch64-linux-gnu" ;;
    armel) echo "arm-linux-gnueabi" ;;
    armhf) echo "arm-linux-gnueabihf" ;;
    i386) echo "i386-linux-gnu" ;;
    mips64el) echo "mips64el-linux-gnuabi64" ;;
    ppc64el) echo "powerpc64le-linux-gnu" ;;
    riscv64) echo "riscv64-linux-gnu" ;;
    s390x) echo "s390x-linux-gnu" ;;
    *) echo "" ;;
    esac
}

# Prints each `update-alternatives --install` a postinst script runs as
#   <order> <name> <priority> <link> <path> [<link> <name> <path>]...
# with one link/name/path triple per --slave. The script is not run: calls are
# read from its text, with continued lines joined, comments dropped, and shell
# variables expanded when the script assigns them a literal value. A call that
# still has anything left for the shell to expand is skipped with a warning.
read -r -d '' PARSE_POSTINST <<'EOF' || true
function unquote(s) {
    gsub(/["']/, "", s)
    return s
}
function expand(s,    out, name) {
    out = ""
    while (match(s, /[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?/)) {
        name = substr(s, RSTART, RLENGTH)
        gsub(/[${}]/, "", name)
        if (!(name in vars)) {
            return out s
        }
        out = out substr(s, 1, RSTART - 1) vars[name]
        s = substr(s, RSTART + RLENGTH)
    }
    return out s
}
BEGIN {
    if (multiarch != "") {
        vars["DEB_HOST_MULTIARCH"] = multiarch
    }
}
{
    line = $0
    if (continued == "" && line ~ /^[ \t]*#/) {
        next
    }
    if (line ~ /\\$/) {
        continued = continued substr(line, 1, length(line) - 1) " "
        next
    }
    line = continued line
    continued = ""

    if (match(line, /[ \t]#/)) {
        line = substr(line, 1, RSTART - 1)
    }
    if (multiarch != "") {
        gsub(/[$][(]dpkg-architecture -qDEB_HOST_MULTIARCH[)]/, multiarch, line)
    }

    if (line ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*=[^ \t;&|]*[ \t]*$/) {
        sub(/^[ \t]+/, "", line)
        sub(/[ \t]+$/, "", line)
        eq = index(line, "=")
        name = substr(line, 1, eq - 1)
        value = expand(unquote(substr(line, eq + 1)))
        if (value ~ /[$`]/) {
            delete vars[name]
        } else {
            vars[name] = value
        }
        next
    }

    gsub(/;|&&|[|][|]?/, " ; ", line)
    n = split(line, t, /[ \t]+/)
    for (i = 1; i <= n; i++) {
        if (t[i] != "update-alternatives" && t[i] !~ /\/update-alternatives$/) {
            continue
        }
        for (j = i + 1; j <= n && t[j] != ";" && t[j] != "--install"; j++) {
        }
        if (t[j] != "--install") {
            continue
        }
        record = expand(unquote(t[j + 2])) " " expand(unquote(t[j + 4])) " " expand(unquote(t[j + 1])) " " expand(unquote(t[j + 3]))
        for (k = j + 5; t[k] == "--slave"; k += 4) {
            record = record " " expand(unquote(t[k + 1])) " " expand(unquote(t[k + 2])) " " expand(unquote(t[k + 3]))
        }
        split(record, fields, " ")
        if (record ~ /[$`]/ || fields[2] !~ /^[0-9]+$/ || fields[3] !~ /^\// || fields[4] !~ /^\//) {
            call = t[i]
            for (m = j; m < k; m++) {
                call = call " " t[m]
            }
            printf("WARNING: %s: skipping `%s`, which cannot be read without running the script\n", package, call) > "/dev/stderr"
        } else {
            print order, record
        }
        i = k
    }
}
EOF

# Settles each alternative the way update-alternatives does in automatic mode,
# which is how packages leave them: the highest priority wins, the first one
# installed on a tie. For the winner, writes an mtree with <link> ->
# /etc/alternatives/<name> -> <path>, and the same for each of its slaves.
read -r -d '' WRITE_MTREE <<'EOF' || true
function usr(path) {
    if (mergedusr == "1" && path ~ /^\/(bin|sbin|lib|lib32|lib64|libx32)\//) {
        return "/usr" path
    }
    return path
}
function link(from, to) {
    printf(".%s type=link uid=0 gid=0 mode=0777 time=1672560000 link=%s\n", usr(from), to)
}
{
    if (!($2 in priority)) {
        names[count++] = $2
    } else if ($3 + 0 <= priority[$2]) {
        next
    }
    priority[$2] = $3 + 0
    winner[$2] = $0
}
END {
    print "#mtree"
    for (i = 0; i < count; i++) {
        n = split(winner[names[i]], f, " ")
        link("/etc/alternatives/" f[2], usr(f[5]))
        link(f[4], "/etc/alternatives/" f[2])
        for (j = 6; j + 2 <= n; j += 3) {
            link("/etc/alternatives/" f[j + 1], usr(f[j + 2]))
            link(f[j], "/etc/alternatives/" f[j + 1])
        }
    }
}
EOF

order=0
for control in "$@"; do
    order=$((order + 1))
    dir="$tmp/$order"
    "$coreutils" mkdir "$dir"
    "$bsdtar" -xf "$control" -C "$dir"
    if [[ ! -f "$dir/postinst" ]]; then
        continue
    fi
    package=$("$awk" '/^Package:/ { print $2; exit }' "$dir/control")
    architecture=$("$awk" '/^Architecture:/ { print $2; exit }' "$dir/control")
    "$awk" -v order="$order" -v package="$package" -v multiarch="$(triplet "$architecture")" \
        "$PARSE_POSTINST" "$dir/postinst"
done | "$awk" -v mergedusr="$mergedusr" "$WRITE_MTREE" >"$tmp/mtree"
"$bsdtar" -cf "$out" --format=gnutar "@$tmp/mtree"
