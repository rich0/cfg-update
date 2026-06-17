# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
#
# Fork development ebuild. Based on ::gentoo app-portage/cfg-update/cfg-update-1.8.9-r3.ebuild.
# Gentoo's uninit-value patch (bugs.gentoo.org/829993) is merged in cfg-update.
# PV 1.9.0 is tagged; 1.9.1 is the current development line — do not tag without approval.
# Stage 5: Paludis maskdir fix, hardened install_all_pre hook script.
# Stage 6c: FEATURES=test integration harness via test/run-tests.sh.

EAPI=8

DESCRIPTION="Easy to use GUI & CLI alternative for etc-update"
HOMEPAGE="https://github.com/rich0/cfg-update"
SRC_URI="https://github.com/rich0/cfg-update/archive/${PV}.tar.gz -> ${P}.tgz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~ppc ~x86"
IUSE="test X"

BDEPEND="
	test? (
		app-shells/bash
		sys-apps/diffutils
		dev-perl/Term-ANSIColor
	)
"

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

src_test() {
	if ! use test; then
		ewarn "Skipping tests (USE=-test)"
		return
	fi

	einfo "Running cfg-update integration test harness"
	"${S}"/test/run-tests.sh --full || die "Integration tests failed"
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
	einfo "meld (default), kdiff3, gtkdiff, gvimdiff, tkdiff, imediff2"
	echo
	einfo "TIP: to maximize the chances of future automatic updates, run:"
	einfo "cfg-update --optimize-backups"
	echo
}
