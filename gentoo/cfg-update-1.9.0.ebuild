# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Fork development ebuild (PV 1.9.0 placeholder until refactor completes).
# Based on ::gentoo app-portage/cfg-update/cfg-update-1.8.9-r3.ebuild:
# https://gitweb.gentoo.org/repo/gentoo.git/tree/app-portage/cfg-update/cfg-update-1.8.9-r3.ebuild
# Gentoo's uninit-value patch (bugs.gentoo.org/829993) is merged in cfg-update.
# Keep PV at 1.9.0 until refactor completes; do not tag for release without maintainer approval.

EAPI=8

DESCRIPTION="Easy to use GUI & CLI alternative for etc-update"
HOMEPAGE="https://github.com/rich0/cfg-update"
SRC_URI="https://github.com/rich0/cfg-update/archive/${PV}.tar.gz -> ${P}.tgz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~ppc ~x86"
IUSE="X"

RDEPEND="
	dev-perl/TermReadKey
	X? (
		>=x11-misc/sux-1.0
		x11-apps/xhost
		)"

S="${WORKDIR}/cfg-update-${PV}"

pkg_prerm() {
	if [[ -z ${ROOT} ]]
	then
		ebegin "Disabling portage hook"
		cfg-update --ebuild --disable-portage-hook
		eend $?
		ebegin "Disabling paludis hook"
		cfg-update --ebuild --disable-paludis-hook
		eend $?
	fi
}

pkg_postrm() {
	echo
	ewarn "If you want to permanently remove cfg-update from your system"
	ewarn "you should remove the index file /var/lib/cfg-update/checksum.index"
	echo
}

src_install() {
	dobin cfg-update
	insinto /usr/lib/cfg-update
	doins cfg-update cfg-update_indexing test.tgz
	dodoc ChangeLog
	doman *.8
	insinto /etc
	doins cfg-update.conf cfg-update.hosts
	keepdir /var/lib/cfg-update
}

pkg_postinst() {
	if [[ ! -e "${ROOT}"/var/lib/cfg-update/checksum.index \
		&& -e "${ROOT}"/var/lib/cfg-update/checksum.index ]]
	then
		ebegin "Moving checksum.index from /usr/lib/cfg-update to /var/lib/cfg-update"
		mv "${ROOT}"/usr/lib/cfg-update/checksum.index \
			"${ROOT}"/var/lib/cfg-update/checksum.index
		eend $?
	fi

	if [[ -z ${ROOT} ]]
	then
		ebegin "Moving backups to /var/lib/cfg-update/backups"
		/usr/bin/cfg-update --ebuild --move-backups
		eend $?
	fi

	echo
	einfo "If this is a first time install, please check the configuration"
	einfo "in /etc/cfg-update.conf before using cfg-update:"
	echo
	einfo "If your system does not have an X-server installed you need to"
	einfo "change the MERGE_TOOL to sdiff, imediff2 or vimdiff."
	einfo "If you have X installed, set MERGE_TOOL to your favorite GUI tool:"
	einfo "xxdiff, beediff, kdiff3, meld (default), gtkdiff, gvimdiff, tkdiff"
	echo
	einfo "TIP: to maximize the chances of future automatic updates, run:"
	einfo "cfg-update --optimize-backups"
	echo
}
