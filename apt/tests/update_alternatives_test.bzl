"tests for update_alternatives"

load("//apt/private:update_alternatives.bzl", "update_alternatives")
load("//distroless/tests:asserts.bzl", "assert_tar_mtree")

_TEST_SUITE_PREFIX = "update_alternatives/"

def _control(name, package, postinst = None, architecture = "amd64"):
    """A control archive for `package`, with `postinst` as its postinst script if given."""
    files = "./control"
    write_postinst = ""
    if postinst:
        files += " ./postinst"
        write_postinst = "cat > \"$$tmpdir/postinst\" << 'EOF'\n" + postinst.replace("$", "$$") + "EOF\n"

    native.genrule(
        name = name,
        outs = [name + ".tar"],
        cmd = """
#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

tmpdir=$$(mktemp -d)
bsdtar="$$(pwd)/$(BSDTAR_BIN)"
out="$$(pwd)/$@"
trap 'rm -rf "$$tmpdir"' EXIT

printf 'Package: {package}\\nVersion: 1.0\\nArchitecture: {architecture}\\n' > "$$tmpdir/control"
{write_postinst}
cd "$$tmpdir"
"$$bsdtar" -cf "$$out" {files}
""".format(
            package = package,
            architecture = architecture,
            write_postinst = write_postinst,
            files = files,
        ),
        toolchains = ["@bsd_tar_toolchains//:resolved_toolchain"],
    )

def update_alternatives_tests():
    # Continued lines, a --slave, and a commented-out --slave, as gcc and mawk have them.
    _control(
        name = "_update_alternatives_gcc",
        package = "gcc",
        postinst = """\
#!/bin/sh
set -e
# update-alternatives --install /usr/bin/commented commented /usr/bin/nothing 99

update-alternatives --quiet \\
    --install /usr/bin/cc cc /usr/bin/gcc 20 \\
    #--slave /usr/share/man/man1/cc.1.gz cc.1.gz /usr/share/man/man1/gcc.1.gz

update-alternatives --install /usr/bin/awk awk /usr/bin/mawk 5 \\
    --slave /usr/bin/nawk nawk /usr/bin/mawk
""",
    )

    # A path spelled with a variable the script assigns.
    _control(
        name = "_update_alternatives_libblas",
        package = "libblas3",
        postinst = """\
#!/bin/sh
set -e
multiarch=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
update-alternatives --install /usr/lib/$multiarch/libblas.so.3 libblas.so.3-$multiarch \\
    /usr/lib/$multiarch/blas/libblas.so.3 10
""",
    )

    # The same alternative at a higher priority, with quotes, braces and a
    # call that cannot be read without running the loop around it.
    _control(
        name = "_update_alternatives_openblas",
        package = "libopenblas0",
        postinst = """\
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    update-alternatives --install "/usr/lib/${DEB_HOST_MULTIARCH}/libblas.so.3" "libblas.so.3-${DEB_HOST_MULTIARCH}" "/usr/lib/${DEB_HOST_MULTIARCH}/openblas/libblas.so.3" 100 || true
fi
for tool in openblas-config; do
    update-alternatives --install /usr/bin/$tool $tool /usr/lib/openblas/$tool 100
done
""",
    )

    # The same priority as mawk's awk, which was listed first and so stays.
    _control(
        name = "_update_alternatives_original_awk",
        package = "original-awk",
        postinst = """\
#!/bin/sh
update-alternatives --install /usr/bin/awk awk /usr/bin/original-awk 5
""",
    )

    _control(
        name = "_update_alternatives_no_postinst",
        package = "base-files",
    )

    update_alternatives(
        name = "_update_alternatives_layer",
        controls = [
            ":_update_alternatives_gcc",
            ":_update_alternatives_libblas",
            ":_update_alternatives_openblas",
            ":_update_alternatives_original_awk",
            ":_update_alternatives_no_postinst",
        ],
    )

    assert_tar_mtree(
        name = _TEST_SUITE_PREFIX + "highest_priority",
        actual = ":_update_alternatives_layer",
        expected = """\
#mtree
./etc/alternatives/awk time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/bin/mawk
./etc/alternatives/cc time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/bin/gcc
./etc/alternatives/libblas.so.3-x86_64-linux-gnu time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/lib/x86_64-linux-gnu/openblas/libblas.so.3
./etc/alternatives/nawk time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/bin/mawk
./usr/bin/awk time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/awk
./usr/bin/cc time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/cc
./usr/bin/nawk time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/nawk
./usr/lib/x86_64-linux-gnu/libblas.so.3 time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/libblas.so.3-x86_64-linux-gnu
""",
    )

    _control(
        name = "_update_alternatives_netcat",
        package = "netcat-openbsd",
        architecture = "arm64",
        postinst = """\
#!/bin/sh
update-alternatives --install /bin/nc nc /bin/nc.openbsd 50 \\
    --slave /lib/${DEB_HOST_MULTIARCH}/libnc.so libnc.so /lib/${DEB_HOST_MULTIARCH}/libnc.openbsd.so
""",
    )

    update_alternatives(
        name = "_update_alternatives_mergedusr_layer",
        controls = [":_update_alternatives_netcat"],
        mergedusr = True,
    )

    assert_tar_mtree(
        name = _TEST_SUITE_PREFIX + "mergedusr",
        actual = ":_update_alternatives_mergedusr_layer",
        expected = """\
#mtree
./etc/alternatives/libnc.so time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/lib/aarch64-linux-gnu/libnc.openbsd.so
./etc/alternatives/nc time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/usr/bin/nc.openbsd
./usr/bin/nc time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/nc
./usr/lib/aarch64-linux-gnu/libnc.so time=1672560000.0 mode=777 gid=0 uid=0 type=link link=/etc/alternatives/libnc.so
""",
    )

    update_alternatives(
        name = "_update_alternatives_empty_layer",
        controls = [":_update_alternatives_no_postinst"],
    )

    assert_tar_mtree(
        name = _TEST_SUITE_PREFIX + "no_postinst",
        actual = ":_update_alternatives_empty_layer",
        # bsdtar describes an empty archive with an empty mtree.
        expected = "",
    )
