"tests for passwd and group with a base"

load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")
load("@bazel_lib//lib:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//distroless:defs.bzl", "group", "passwd")

_TEST_SUITE_PREFIX = "base_file/"

def _layer(name, files, out = None):
    """A tar of `files`, a dict of path to content, with each path as given ("./etc/passwd" or "etc/passwd")."""
    write = "".join([
        "mkdir -p \"$$tmpdir/$$(dirname {path})\"\nprintf '%b' '{content}' > \"$$tmpdir/{path}\"\n".format(path = path, content = content)
        for path, content in files.items()
    ])
    native.genrule(
        name = name,
        outs = [out or name + ".tar"],
        cmd = """
#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

tmpdir=$$(mktemp -d)
bsdtar="$$(pwd)/$(BSDTAR_BIN)"
out="$$(pwd)/$@"
trap 'rm -rf "$$tmpdir"' EXIT

{write}
cd "$$tmpdir"
"$$bsdtar" -cf "$$out" {paths}
""".format(write = write, paths = " ".join(files.keys())),
        toolchains = ["@bsd_tar_toolchains//:resolved_toolchain"],
    )

def _expect(name, actual, lines):
    write_file(
        name = "_%s_expected" % name,
        out = "_%s.expected" % name,
        content = lines + [""],
        newline = "unix",
    )
    diff_test(
        name = _TEST_SUITE_PREFIX + name,
        file1 = actual,
        file2 = ":_%s_expected" % name,
        timeout = "short",
    )

def base_file_tests():
    # A tar of a root filesystem, whose /etc/passwd has no last newline.
    _layer(
        name = "_base_file_rootfs",
        files = {
            "./etc/group": "root:x:0:\\nnogroup:x:65534:\\n",
            "./etc/passwd": "root:x:0:0:root:/root:/bin/bash\\nnobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin",
        },
    )

    passwd(
        name = "_base_file_passwd_tar",
        base = ":_base_file_rootfs",
        entries = [
            dict(gid = 10001, uid = 10001, home = "/home/app", shell = "/bin/sh", username = "app"),
        ],
    )

    _expect(
        name = "passwd_tar",
        actual = ":_base_file_passwd_tar_content",
        lines = [
            "root:x:0:0:root:/root:/bin/bash",
            "nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin",
            "app:!:10001:10001::/home/app:/bin/sh",
        ],
    )

    group(
        name = "_base_file_group_tar",
        base = ":_base_file_rootfs",
        entries = [
            dict(name = "app", gid = 10001),
        ],
    )

    _expect(
        name = "group_tar",
        actual = ":_base_file_group_tar_content",
        lines = [
            "root:x:0:",
            "nogroup:x:65534:",
            "app:!:10001:",
        ],
    )

    # An OCI image layout of three layers: the oldest and the middle one each
    # have an /etc/passwd, the newest has none. The blobs are named by made-up
    # digests; nothing here checks them.
    _layer(
        name = "_base_file_layer_old",
        out = "_base_file_layout_files/blobs/sha256/old",
        files = {"./etc/passwd": "root:x:0:0:root:/root:/bin/sh\\nold:x:1:1::/:/bin/false\\n"},
    )
    _layer(
        name = "_base_file_layer_middle",
        out = "_base_file_layout_files/blobs/sha256/middle",
        files = {
            "etc/group": "root:x:0:\\n",
            "etc/passwd": "root:x:0:0:root:/root:/bin/bash\\nnobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\\n",
        },
    )
    _layer(
        name = "_base_file_layer_new",
        out = "_base_file_layout_files/blobs/sha256/new",
        files = {"./etc/hostname": "localhost\\n"},
    )
    write_file(
        name = "_base_file_manifest",
        out = "_base_file_layout_files/blobs/sha256/manifest",
        content = [json.encode({
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": "sha256:config", "size": 0},
            "layers": [
                {"mediaType": "application/vnd.oci.image.layer.v1.tar", "digest": "sha256:" + layer, "size": 0}
                for layer in ["old", "middle", "new"]
            ],
        })],
    )
    write_file(
        name = "_base_file_index",
        out = "_base_file_layout_files/index.json",
        content = [json.encode({
            "schemaVersion": 2,
            "manifests": [{"mediaType": "application/vnd.oci.image.manifest.v1+json", "digest": "sha256:manifest", "size": 0}],
        })],
    )
    copy_to_directory(
        name = "_base_file_layout",
        srcs = [
            ":_base_file_index",
            ":_base_file_layer_middle",
            ":_base_file_layer_new",
            ":_base_file_layer_old",
            ":_base_file_manifest",
        ],
        root_paths = ["distroless/tests/_base_file_layout_files"],
    )

    passwd(
        name = "_base_file_passwd_layout",
        base = ":_base_file_layout",
        entries = [
            dict(gid = 10001, uid = 10001, home = "/home/app", shell = "/bin/sh", username = "app"),
        ],
    )

    _expect(
        name = "passwd_layout",
        actual = ":_base_file_passwd_layout_content",
        lines = [
            "root:x:0:0:root:/root:/bin/bash",
            "nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin",
            "app:!:10001:10001::/home/app:/bin/sh",
        ],
    )
