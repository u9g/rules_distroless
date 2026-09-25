"EXPERIMENTAL! Public API"

load("//apt/private:dpkg_status.bzl", _dpkg_status = "dpkg_status")
load("//apt/private:dpkg_statusd.bzl", _dpkg_statusd = "dpkg_statusd")
load("//apt/private:update_alternatives.bzl", _update_alternatives = "update_alternatives")

dpkg_status = _dpkg_status
dpkg_statusd = _dpkg_statusd
update_alternatives = _update_alternatives
