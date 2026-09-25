"update_alternatives"

# buildifier: disable=bzl-visibility
load("//distroless/private:tar.bzl", "tar_lib")

_DOC = """Makes the symlinks `update-alternatives --install` would have made for the packages.

Package maintainer scripts are not run when rules_distroless installs packages,
so links that a package's `postinst` creates with `update-alternatives`, such as
`/usr/bin/awk` from `mawk` or `/usr/bin/cc` from `gcc`, are missing. This rule
reads each package's `postinst` for its `update-alternatives --install` calls
without running it, and settles each alternative the way `update-alternatives`
does in automatic mode: the highest priority wins, and the package listed first
wins a tie. For each winner it writes `<link> -> /etc/alternatives/<name> ->
<path>`, and the same for each of its `--slave` links.

A call whose arguments the shell would have to compute, such as one inside a
`for` loop over a variable, is skipped with a warning. Variables the script
assigns a literal value, and `$(dpkg-architecture -qDEB_HOST_MULTIARCH)`, are
expanded.

`apt.install` generates one of these for every dependency set as
`@<dependency_set>//:update_alternatives`, over all of the set's packages.

```starlark
load("@rules_distroless//apt:defs.bzl", "update_alternatives")

update_alternatives(
    name = "alternatives",
    controls = [
        "@bookworm//gcc/amd64:control",
        "@bookworm//mawk/amd64:control",
    ],
)
```
"""

def _update_alternatives_impl(ctx):
    bsdtar = ctx.toolchains[tar_lib.TOOLCHAIN_TYPE]
    coreutils = ctx.toolchains["@bazel_lib//lib:coreutils_toolchain_type"]

    output = ctx.actions.declare_file(ctx.attr.name + ".tar")

    args = ctx.actions.args()
    args.add(bsdtar.tarinfo.binary)
    args.add(output)
    args.add(ctx.executable._awk.path)
    args.add(coreutils.coreutils_info.bin)
    args.add("1" if ctx.attr.mergedusr else "0")
    args.add_all(ctx.files.controls)

    ctx.actions.run(
        executable = ctx.executable._update_alternatives_sh,
        inputs = ctx.files.controls,
        outputs = [output],
        tools = [
            bsdtar.default.files,
            ctx.executable._awk,
            coreutils.default.files,
        ],
        arguments = [args],
        mnemonic = "UpdateAlternatives",
        progress_message = "Reading update-alternatives calls for %{label}",
    )

    return [
        DefaultInfo(files = depset([output])),
    ]

update_alternatives = rule(
    doc = _DOC,
    attrs = {
        "controls": attr.label_list(
            doc = "The packages' control archives, in order of preference for alternatives of equal priority.",
            allow_files = [".tar.zst", ".tar.xz", ".tar.gz", ".tar"],
            mandatory = True,
        ),
        "mergedusr": attr.bool(
            doc = "Move links, and the paths they point to, from /bin, /sbin and /lib* to their /usr counterparts, as `apt.install(mergedusr = True)` does with package files.",
            default = False,
        ),
        "_update_alternatives_sh": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            default = ":update_alternatives.sh",
        ),
        "_awk": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            default = "@ape//ape:awk",
        ),
    },
    implementation = _update_alternatives_impl,
    toolchains = [tar_lib.TOOLCHAIN_TYPE, "@bazel_lib//lib:coreutils_toolchain_type"],
)
