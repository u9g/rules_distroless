"group"

load("@bazel_lib//lib:utils.bzl", "propagate_common_rule_attributes")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@tar.bzl//tar:tar.bzl", "tar")
load(":base_file.bzl", "base_file")
load(":tar.bzl", "tar_lib")
load(":util.bzl", "util")

def group(name, entries, time = "0.0", mode = "0644", base = None, **kwargs):
    """
    Create a group file from array of dicts.

    https://www.ibm.com/docs/en/aix/7.2?topic=files-etcgroup-file#group_security__a21597b8__title__1

    Args:
        name: name of the target
        entries: an array of dicts which will be serialized into single group file.
        mode: mode for the entry
        time: time for the entry
        base: an image to add the entries to, as `groupadd` would: an OCI image layout,
            such as `oci.pull` or `oci_image` makes, or a tar of a root filesystem.
            The file is then the base's /etc/group, from the newest layer that has it,
            followed by the entries, none of which may name a group the base has.
            Without it, the file has only the entries.
        **kwargs: other named arguments to expanded targets. see [common rule attributes](https://bazel.build/reference/be/common-definitions#common-attributes).
    """
    common_kwargs = propagate_common_rule_attributes(kwargs)
    write_file(
        name = "%s_entries" % name if base else "%s_content" % name,
        content = [
            # See https://www.ibm.com/docs/en/aix/7.2?topic=files-etcgroup-file#group_security__a3179518__title__1
            ":".join([
                util.get_attr(entry, "name"),
                util.get_attr(entry, "password", "!"),  # not used. Group administrators are provided instead of group passwords.
                str(util.get_attr(entry, "gid")),
                ",".join(util.get_attr(entry, "users", [])),
            ])
            for entry in entries
        ] + [""],
        out = "%s.entries" % name if base else "%s.content" % name,
        **common_kwargs
    )

    if base:
        base_file(
            name = "%s_content" % name,
            base = base,
            path = "/etc/group",
            lines = ":%s_entries" % name,
            out = "%s.content" % name,
            **common_kwargs
        )

    mtree = tar_lib.create_mtree()

    # TODO: We should have a rule `rootfs` that creates the filesystem root.
    # We'll add this for now to match distroless images.
    mtree.add_dir("/etc", mode = "0755", time = time)
    mtree.entry(
        "/etc/group",
        "file",
        mode = mode,
        time = time,
        content = "$(execpath :%s_content)" % name,
    )

    tar(
        name = name,
        srcs = [":%s_content" % name],
        mtree = mtree.content(),
        args = tar_lib.DEFAULT_ARGS,
        compress = "gzip",
        **common_kwargs
    )
