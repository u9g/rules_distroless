"base_file"

load(":tar.bzl", "tar_lib")

_YQ_TOOLCHAIN_TYPE = "@yq.bzl//yq/toolchain:type"

def _base_file_impl(ctx):
    bsdtar = ctx.toolchains[tar_lib.TOOLCHAIN_TYPE]
    coreutils = ctx.toolchains["@bazel_lib//lib:coreutils_toolchain_type"]
    yq = ctx.toolchains[_YQ_TOOLCHAIN_TYPE]

    output = ctx.actions.declare_file(ctx.attr.out)

    args = ctx.actions.args()
    args.add(bsdtar.tarinfo.binary)
    args.add(yq.yqinfo.bin)
    args.add(ctx.executable._awk.path)
    args.add(coreutils.coreutils_info.bin)
    args.add(ctx.file.base.path)
    args.add(ctx.attr.path)
    args.add(ctx.file.lines)
    args.add(output)

    ctx.actions.run(
        executable = ctx.executable._base_file_sh,
        inputs = [ctx.file.base, ctx.file.lines],
        outputs = [output],
        tools = [
            bsdtar.default.files,
            yq.default.files,
            ctx.executable._awk,
            coreutils.default.files,
        ],
        arguments = [args],
        mnemonic = "BaseFile",
        progress_message = "Adding to %s from %s" % (ctx.attr.path, ctx.attr.base.label),
    )

    return [DefaultInfo(files = depset([output]))]

base_file = rule(
    doc = "Private. A file as a base image has it, with `lines` added after it: /etc/passwd with a user, say.",
    attrs = {
        "base": attr.label(
            doc = "An OCI image layout, such as `oci.pull` or `oci_image` makes, or a tar of a root filesystem.",
            allow_single_file = True,
            mandatory = True,
        ),
        "path": attr.string(
            doc = "The file's absolute path in the image.",
            mandatory = True,
        ),
        "lines": attr.label(
            doc = "A file of the lines to add.",
            allow_single_file = True,
            mandatory = True,
        ),
        "out": attr.string(mandatory = True),
        "_base_file_sh": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            default = ":base_file.sh",
        ),
        "_awk": attr.label(
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            default = "@ape//ape:awk",
        ),
    },
    implementation = _base_file_impl,
    toolchains = [
        tar_lib.TOOLCHAIN_TYPE,
        "@bazel_lib//lib:coreutils_toolchain_type",
        _YQ_TOOLCHAIN_TYPE,
    ],
)
