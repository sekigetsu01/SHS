#!/bin/bash
# SHS - Sekigetsu's Host Setup
# Run on a fresh Arch Linux (or Artix) installation, from the user you made while installing:
#   sudo sh shs.sh            asks a few questions first, then runs by itself
#   sudo sh shs.sh -y         no questions: installs everything but Whonix (its licence needs your yes)
#   sudo sh shs.sh -u NAME    set up NAME (when there's more than one user)
# It sets up that user (no new username or password needed). With an encrypted disk it also logs it in automatically
# at boot (you've typed the disk's password already); without one, ly asks for your password.

# Run with bash (not bash's sh mode) even when started with 'sh shs.sh'.
if [ -z "$BASH_VERSION" ] || shopt -qo posix 2>/dev/null; then exec bash "$0" "$@"; fi


# CONFIGURATION

DOTFILES="https://github.com/sekigetsu01/hostrice.git"
WALLPAPERS="https://github.com/sekigetsu01/wallpapers.git"   # into ~/wallpapers (wallpaper picks from there)
PROGSFILE="https://raw.githubusercontent.com/sekigetsu01/SHS/main/static/progs.csv"
AURHELPER="yay"
BRANCH="main"
SESSION="mango"            # desktop session ly logs into automatically
LOG=/var/log/shs.log       # everything the installs print, to see why something failed
MIN_FREE_GB=20             # free space needed on / (the VM tools are big)
WORK=/tmp/shs              # the programs list and progress while it runs
WHONIX="https://download.whonix.org/libvirt"   # Whonix's KVM releases, one folder per version
WHONIX_KEY="https://www.whonix.org/keys/derivative.asc"
WHONIX_FPR="916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA"   # Patrick Schleizer's key, which signs every release
WHONIX_GB=8                # more free space it needs (the 2 GB download, unpacked next to it)
# whiptail needs a description of the terminal: one this system has none for (kitty over ssh, say) is drawn as plain ANSI
infocmp "$TERM" >/dev/null 2>&1 || export TERM=ansi
# Dark screens that stay readable in any terminal colours (pywal's too): light text only on black, black text on any
# colour. The progress bar's percentage is always white (newt), so both parts of the bar are dark: with 256 colours,
# shades that colour schemes don't change; on the console's 8, blue (dark there) and black
bar_full=blue bar_empty=black
if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ]; then bar_full=color24 bar_empty=color236; fi
export NEWT_COLORS="
root=lightgray,black
roottext=lightgray,black
helpline=lightgray,black
border=cyan,black
window=lightgray,black
shadow=black,black
title=cyan,black
textbox=lightgray,black
acttextbox=black,cyan
label=lightgray,black
button=black,lightgray
actbutton=black,cyan
compactbutton=lightgray,black
entry=black,cyan
disentry=lightgray,black
checkbox=lightgray,black
actcheckbox=black,cyan
listbox=lightgray,black
actlistbox=black,cyan
sellistbox=black,cyan
actsellistbox=black,cyan
emptyscale=lightgray,$bar_empty
fullscale=lightgray,$bar_full
"


# OPTIONS

yes=0 name=""
usage() {
	sed -n '4,6s/^#   //p' "$0" >&2
	exit 1
}
while [ $# -gt 0 ]; do
	case $1 in
		-y|--yes) yes=1 ;;
		-u|--user) name=$2; shift; [ -n "$name" ] || usage ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
	shift
done


# UTILITIES

die() { clear 2>/dev/null; printf "shs: %s\n" "$1" >&2; exit 1; }


# whiptail with the step line at the top of the screen
BACK="SHS"
step_line() { BACK="SHS  ·  step $1 of 3: $2"; }
wt() {
	local a
	# typing (a name, passwords) and the progress bar: whiptail as it is, so h and l are just letters there
	for a; do
		case $a in --inputbox|--passwordbox|--gauge) whiptail --backtitle "$BACK" "$@"; return ;; esac
	done
	[ -t 0 ] && command -v script >/dev/null || { whiptail --backtitle "$BACK" "$@"; return; }
	wt_hl "$@"
}

# h / l move between the buttons (whiptail itself only knows the arrows and Tab): it runs in a terminal of its
# own (script), and the keys you press reach it through hl_keys, h and l turned into ← and →. What it picks (a menu)
# comes back through a file, out on stderr as whiptail puts it.
hl_keys() {
	local k
	while :; do
		IFS= read -rn1 -d '' k || continue
		case $k in h) printf '\e[D' ;; l) printf '\e[C' ;; $'\n') printf '\r' ;; *) printf '%s' "$k" ;; esac
	done
}
wt_hl() {
	local size saved in kp rc out=$WORK/wt-out
	size=$(stty size) saved=$(stty -g)
	stty -icanon -echo -icrnl min 1
	exec {in}< <(hl_keys)
	kp=$!
	SHELL=/bin/bash script -qefc "stty rows ${size% *} cols ${size#* }; exec whiptail --output-fd 3 $(printf '%q ' --backtitle "$BACK" "$@") 3>$(printf '%q' "$out")" /dev/null <&"$in"
	rc=$?
	kill "$kp" 2>/dev/null
	exec {in}<&-
	stty "$saved"
	[ -s "$out" ] && cat "$out" >&2
	rm -f "$out"
	return "$rc"
}

pac() { pacman --noconfirm --needed "$@" >>"$LOG" 2>&1; }

# Description of a program in the list, without the quotes
describe() { awk -F, -v p="$1" '$2 == p { sub(/^[^,]*,[^,]*,/, ""); gsub(/^"|"$/, ""); print; exit }' "$WORK/progs.csv"; }


# CHECKS BEFORE ANYTHING ELSE

preflight() {
	(( EUID == 0 )) || die "run it with sudo: sudo sh shs.sh"
	command -v pacman >/dev/null && { [ -f /etc/arch-release ] || [ -f /etc/artix-release ]; } ||
		die "this is for Arch Linux or Artix (no pacman, arch-release or artix-release found)."
	# Arch has systemd; Artix has runit, OpenRC or dinit instead (services, the clock and dbus are done their way)
	systemd=0; [ -d /run/systemd/system ] && systemd=1
	artix=0; [ -f /etc/artix-release ] && artix=1
	curl -fsI --max-time 15 https://archlinux.org >/dev/null 2>&1 ||
		curl -fsI --max-time 15 https://github.com >/dev/null 2>&1 ||
		die "no internet connection (couldn't reach archlinux.org or github.com)."
	free=$(df -Pk / | awk 'NR == 2 { print int($4 / 1048576) }')
	(( free >= MIN_FREE_GB )) || die "not enough free space: ${free} GB on /, it needs at least ${MIN_FREE_GB} GB."
	# a pacman lock left by a crash (not one in use) would stop every install
	if [ -e /var/lib/pacman/db.lck ]; then
		pgrep -x 'pacman|yay|makepkg' >/dev/null && die "pacman is busy in another window: let it finish first."
		rm -f /var/lib/pacman/db.lck
	fi
	mkdir -p "$WORK" && : > "$LOG" || die "couldn't write $LOG"
	# whiptail itself
	# (from the package list the install left, not -Sy: refreshing it and installing one package is a partial upgrade;
	# only when that list is too old to download from is the whole system updated first)
	command -v whiptail >/dev/null || pacman --noconfirm -S --needed libnewt >>"$LOG" 2>&1 ||
		pacman --noconfirm -Syu --needed libnewt >>"$LOG" 2>&1 ||
		die "couldn't install whiptail (libnewt); see $LOG"
	# an encrypted disk (LUKS under /): you type its password at boot, so logging in again after is skipped
	encrypted=0
	lsblk -nso TYPE "$(findmnt -nvo SOURCE /)" 2>/dev/null | grep -qx crypt && encrypted=1
}


# QUESTIONS

welcome() {
	(( yes )) && return 0
	wt --title "Welcome to SHS!" --yes-button "Continue" --no-button "Cancel" --yesno \
		"Welcome to Sekigetsu's Host Setup.\n\nThis sets up a full desktop for your user, ready to run virtual machines: programs, dotfiles, and the login screen.\n\nA few questions first, then it runs by itself.\n\n-Sekigetsu" 14 65
}

# The user to set up: -u NAME, else the one who ran 'sudo sh shs.sh', else the only user made during
# the install, else a pick from the users there are. Only asks for a new username and password
# if there are no users at all.
get_user() {
	[ -n "$name" ] || name=${SUDO_USER:-}
	[ "$name" = root ] && name=""
	if [ -n "$name" ]; then
		id -u "$name" >/dev/null 2>&1 || die "there's no user called '$name'."
		return 0
	fi
	mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" { print $1 }' /etc/passwd)
	if (( ${#users[@]} == 1 )); then
		name=${users[0]}
	elif (( ${#users[@]} > 1 )); then
		(( yes )) && die "more than one user here: say which with -u NAME."
		local items=() u
		for u in "${users[@]}"; do items+=("$u" ""); done
		name=$(wt --title "Which user?" --nocancel --menu "Set up the desktop for:" 15 50 6 "${items[@]}" 3>&1 1>&2 2>&3) || exit 1
	else
		(( yes )) && die "there's no user yet: make one, or run it without -y to make one here."
		new_user=1
		get_credentials
	fi
}

get_credentials() {
	name=$(wt --inputbox "No user found. Enter a username for the new account." 10 60 3>&1 1>&2 2>&3) || exit 1
	until [[ $name =~ ^[a-z_][a-z0-9_-]*$ ]]; do
		name=$(wt --nocancel --inputbox "Invalid username. Use lowercase letters, numbers, - or _ only. Must start with a letter." \
			10 65 3>&1 1>&2 2>&3)
	done
	pass1=$(wt --nocancel --passwordbox "Enter a password for '$name'." 10 60 3>&1 1>&2 2>&3)
	pass2=$(wt --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3)
	while [ -z "$pass1" ] || [ "$pass1" != "$pass2" ]; do
		pass1=$(wt --nocancel --passwordbox "Passwords were empty or didn't match. Try again." 10 60 3>&1 1>&2 2>&3)
		pass2=$(wt --nocancel --passwordbox "Confirm password." 10 60 3>&1 1>&2 2>&3)
	done
}

# A passphrase for the new SSH key. It stays in this script's memory only (never on disk, in the
# log or on a command line) and is fed to ssh-keygen through a pipe. Skip: no key is made.
get_ssh_pass() {
	ssh_make=0 ssh_pass="" ssh_have=0
	local h p2
	h=$(getent passwd "$name" | cut -d: -f6)
	[ -n "$h" ] && [ -e "$h/.ssh/id_ed25519" ] && { ssh_have=1; return 0; }
	(( yes )) && return 0
	while :; do
		ssh_pass=$(wt --title "SSH key" --cancel-button "Skip" --passwordbox \
			"SHS makes you an SSH key (for GitHub, servers and your VMs). Choose its passphrase: you type it once per login.\n\nSkip: no key." \
			12 68 3>&1 1>&2 2>&3) || { ssh_pass=""; return 0; }
		p2=$(wt --title "SSH key" --nocancel --passwordbox "Same passphrase again." 9 68 3>&1 1>&2 2>&3)
		if [ "$ssh_pass" != "$p2" ]; then
			wt --title "SSH key" --msgbox "The passphrases didn't match. Try again." 8 50
			continue
		fi
		[ -n "$ssh_pass" ] && break
		wt --title "SSH key" --yes-button "No passphrase" --no-button "Back" --yesno \
			"No passphrase?\n\nAnyone who gets a copy of the key file can use it." 10 60 && break
	done
	unset p2
	ssh_make=1
}

# Whonix: two VMs, a Gateway that runs Tor and a Workstation whose every connection goes through it. A 2 GB
# download, and its licence is yours to accept, so it's asked (and left out with -y)
ask_whonix() {
	whonix=0
	(( yes )) && return 0
	wt --title "Whonix" --yes-button "Install it" --no-button "Skip" --yesno \
		"Also install Whonix?\n\nTwo VMs: a Gateway that runs Tor, and a Workstation whose every connection goes through it. It's a 2 GB download (with a desktop), checked against Whonix's signature, ready in virt-manager.\n\nInstalling it means you accept Whonix's licence:\nhttps://www.whonix.org/wiki/License_Agreement" 16 70 || return 0
	(( free >= MIN_FREE_GB + WHONIX_GB )) ||
		die "not enough free space for Whonix too: ${free} GB on /, it needs $((MIN_FREE_GB + WHONIX_GB)) GB (or skip Whonix)."
	whonix=1
}

get_progs() {
	# The progs.csv next to this script if there is one (so your edits are used), else the one on GitHub.
	local here
	here=$(dirname "$(readlink -f "$0")")
	if [ -f "$here/progs.csv" ]; then
		cat "$here/progs.csv"
	else
		curl -fLs --max-time 60 "$PROGSFILE"
	fi | tr -d '\r' | sed '/^#/d;/^[[:space:]]*$/d' > "$WORK/progs.csv"
	[ -s "$WORK/progs.csv" ] || die "couldn't get the programs list (progs.csv)."
}

# The list of what to install, split by how
plan() {
	local tag program
	repo=() other=()
	while IFS=, read -r tag program _; do
		case $tag in
			"") repo+=("$program") ;;
			*) other+=("$tag,$program") ;;
		esac
	done < "$WORK/progs.csv"
}

summary() {
	local aur=0 flat=0 rest=0 t minutes login_text system_text
	for t in "${other[@]}"; do
		case ${t%%,*} in A) aur=$((aur + 1)) ;; F) flat=$((flat + 1)) ;; *) rest=$((rest + 1)) ;; esac
	done
	# rough: the system update and repo packages, each AUR build, and the dotfiles' own setup
	minutes=$(( 8 + ${#repo[@]} / 15 + aur * 2 + flat + rest + 10 ))
	(( yes )) && return 0
	if (( ssh_have )); then ssh_text="the one you have (~/.ssh/id_ed25519)"
	elif (( ! ssh_make )); then ssh_text="none (skipped)"
	elif [ -n "$ssh_pass" ]; then ssh_text="a new one, with your passphrase"
	else ssh_text="a new one, no passphrase"; fi
	if (( encrypted )); then login_text="automatic (your disk is encrypted)"
	else login_text="ly asks for your password (no encrypted disk)"; fi
	if (( artix )); then system_text="Artix (Arch repos added)"; else system_text="Arch Linux"; fi
	wt --title "Ready to install" --yes-button "Start" --no-button "Cancel" --yesno \
"For:            $name$([ -n "${new_user:-}" ] && echo " (new user)")
System:         $system_text
Programs:       ${#repo[@]} from the Arch repos, $aur from the AUR, $flat flatpaks$( (( rest )) && echo ", $rest other")
SSH key:        $ssh_text
Login at boot:  $login_text
VMs:            libvirtd on, you in the libvirt group, Caps Lock as Esc (the spice fix)
DNS:            encrypted and anonymized (DNSCrypt)
Whonix:         $( (( whonix )) && echo "yes: the latest release, into ~/VMs" || echo "no")
Then:           your dotfiles, wallpapers, then their own setup and clean-up

Roughly $minutes minutes, depending on your internet.
It runs by itself from here. The log is $LOG." 20 76
}


# THE INSTALL (runs under the progress bar; everything it prints goes to the log)

# progress: everything has a weight; the bar shows how much of the total weight is done
progress_init() {
	local t
	total_w=$(( 6 + 1 + 3 + ${#repo[@]} + 2 + 2 + 1 + 2 + 2 + 12 + 2 ))
	(( whonix )) && total_w=$(( total_w + 15 ))
	for t in "${other[@]}"; do
		case ${t%%,*} in A|S) total_w=$((total_w + 4)) ;; *) total_w=$((total_w + 3)) ;; esac
	done
	done_w=0 started=$(date +%s)
}
show() {   # show LINE1 [LINE2]: what it's doing now, with the bar
	local pct left="" elapsed
	pct=$(( done_w * 100 / total_w )); (( pct > 99 )) && pct=99
	elapsed=$(( $(date +%s) - started ))
	if (( pct >= 5 && elapsed > 60 )); then
		left=$(( elapsed * (total_w - done_w) / done_w / 60 + 1 ))
		left="  ·  about $left min left"
	fi
	# one text line, with whiptail's own \n for the line breaks
	printf 'XXX\n%d\n%s%s\\n\\n%s\nXXX\n' "$pct" "$1" "$left" "${2:-}" >&3
}
advance() { done_w=$(( done_w + $1 )); }
fail() { echo "$1" >> "$WORK/failed"; }

# Artix: the Arch repos next to its own (most programs here come from them), through artix-archlinux-support
artix_repos() {
	# Artix's [universe] first (extra packages of its own, and where the old SHS got artix-archlinux-support from)
	grep -q '^\[universe\]' /etc/pacman.conf || cat >> /etc/pacman.conf << 'EOF'

[universe]
Server = https://universe.artixlinux.org/$arch
Server = https://mirror1.artixlinux.org/universe/$arch
Server = https://mirror.pascalpuffke.de/artix-universe/$arch
EOF
	pac -Sy artix-keyring artix-archlinux-support || return 1
	# [extra] is the Arch repo (there's no [community] any more: it was merged into [extra], and a repo that
	# isn't there stops every pacman -Sy)
	grep -q '^\[extra\]' /etc/pacman.conf ||
		printf '\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch\n' >> /etc/pacman.conf
	pacman-key --populate archlinux >>"$LOG" 2>&1
}

update_system() {
	show "Updating the system" "keyring, then all packages (a fresh install's packages can be old)"
	if (( artix )); then
		artix_repos || { fail "the Arch repos for Artix (artix-archlinux-support)"; fail "system update"; return 1; }
	else
		pac -Sy archlinux-keyring
	fi
	# colour, 5 downloads at once, all CPU cores for builds
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
	sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf
	# a full update before installing anything (installing onto an old system can break it)
	# (tried twice: a mirror that drops out is the usual reason; still failing, nothing else is installed)
	pacman -Syu --noconfirm >>"$LOG" 2>&1 || pacman -Syu --noconfirm >>"$LOG" 2>&1 ||
		{ fail "system update"; return 1; }
	advance 6

	# sudo too: everything after this runs your builds through it (an install logged in as root may not have it)
	show "Installing the basics" "curl, base-devel, git, zsh, sudo"
	pac -S curl ca-certificates base-devel git zsh sudo || fail "base-devel / git / zsh / sudo"
	# the clock kept right from a time server: systemd's own, or ntp on Artix
	if (( systemd )); then
		timedatectl set-ntp true >>"$LOG" 2>&1
	else
		pac -S ntp && ntpd -q -g >>"$LOG" 2>&1
	fi
	advance 1
}

setup_user() {
	if [ -n "${new_user:-}" ]; then
		useradd -m -G wheel -s /bin/zsh "$name" >>"$LOG" 2>&1 || { fail "creating the user $name"; return 1; }
		echo "$name:$pass1" | chpasswd
		unset pass1 pass2
	else
		usermod -aG wheel "$name"
	fi
	chsh -s /bin/zsh "$name" >>"$LOG" 2>&1
	group=$(id -gn "$name")
	home=$(getent passwd "$name" | cut -d: -f6)
	export REPODIR="$home/.local/src"
	# ISOs and VMs: where virt-manager's installers and disks go (the README's KVM steps give them to libvirt)
	as_user mkdir -p "$REPODIR" "$home/Downloads" "$home/Documents" "$home/Passwords" "$home/ISOs" "$home/VMs" \
		"$home/github" "$home/.cache/zsh"
	# AUR builds run as you and need sudo for pacman: allowed without a password until the end. The lasting rule
	# (sudo with your password) goes in now too, so a stop half way (Ctrl+C, a crash) never leaves you without sudo
	# verifypw/listpw=any: 'sudo -v' (scripts that start with it) passes on this one passwordless rule;
	# by default every rule must be passwordless, so the lasting one made it ask, unseen behind the progress bar
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-sudo
	printf '%s\n' "Defaults verifypw=any, listpw=any" "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/shs-temp
	chmod 440 /etc/sudoers.d/00-wheel-sudo /etc/sudoers.d/shs-temp
}

as_user() { sudo -u "$name" -H "$@"; }

# a system service on (at the next boot) or off, the way this system's init does it. Artix needs the service's
# package for its init first (ly-runit, libvirt-openrc…)
init_name() { basename "$(readlink -f /sbin/init)"; }
service_on() {
	local s=$1 unit=${2:-$1.service}
	if (( systemd )); then systemctl enable "$unit" >>"$LOG" 2>&1; return; fi
	case $(init_name) in
		runit*) pac -S "$s-runit" && ln -sfn "/etc/runit/sv/$s" /etc/runit/runsvdir/default/ ;;
		openrc*) pac -S "$s-openrc" && rc-update add "$s" default >>"$LOG" 2>&1 ;;
		dinit*) pac -S "$s-dinit" && mkdir -p /etc/dinit.d/boot.d && ln -sf "/etc/dinit.d/$s" /etc/dinit.d/boot.d/ ;;
		*) false ;;
	esac
}
# a service started now as well (runit starts what's linked in by itself)
service_start() {
	if (( systemd )); then systemctl start "$1.service" >>"$LOG" 2>&1; return; fi
	case $(init_name) in
		openrc*) rc-service "$1" start >>"$LOG" 2>&1 ;;
		dinit*) dinitctl start "$1" >>"$LOG" 2>&1 ;;
	esac
}
service_off() {
	if (( systemd )); then systemctl disable --now "$1.service" >>"$LOG" 2>&1; return 0; fi
	case $(init_name) in
		runit*) rm -f "/etc/runit/runsvdir/default/$1" ;;
		openrc*) rc-update del "$1" default >>"$LOG" 2>&1 ;;
		dinit*) rm -f "/etc/dinit.d/boot.d/$1" ;;
	esac
	return 0
}

aur_helper() {
	show "Building $AURHELPER" "installs programs from the AUR"
	if ! command -v "$AURHELPER" >/dev/null; then
		local dir=$REPODIR/$AURHELPER
		rm -rf "$dir"
		as_user git clone --depth 1 -q "https://aur.archlinux.org/$AURHELPER.git" "$dir" >>"$LOG" 2>&1 &&
			(cd "$dir" && as_user makepkg -sif --noconfirm >>"$LOG" 2>&1) ||
			{ fail "$AURHELPER"; return 1; }
	fi
	advance 3
}

repo_packages() {
	# One pacman run for every repo package (much faster than one each). Names pacman doesn't know
	# (renamed or a typo) are tried on their own afterwards, so one bad name doesn't stop the rest.
	(( ${#repo[@]} )) || return 0
	local known=() unknown=() p line n m base=$done_w count=${#repo[@]}
	declare -A in_repos
	while read -r p; do in_repos[$p]=1; done < <(pacman -Slq 2>/dev/null)
	for p in "${repo[@]}"; do
		if [ -n "${in_repos[$p]:-}" ] || pacman -Sgq "$p" >/dev/null 2>&1; then known+=("$p"); else unknown+=("$p"); fi
	done
	show "Installing ${#known[@]} programs from the Arch repos" "downloading..."
	LC_ALL=C pacman -S --noconfirm --needed "${known[@]}" 2>&1 | tee -a "$LOG" | while IFS= read -r line; do
		# pacman prints "(12/340) installing name" for each package (dependencies included)
		if [[ $line =~ ^\(\ *([0-9]+)/\ *([0-9]+)\)\ (installing|upgrading|reinstalling)\ ([^ .]+) ]]; then
			n=${BASH_REMATCH[1]} m=${BASH_REMATCH[2]}
			done_w=$(( base + count * n / m ))
			show "Installing from the Arch repos ($n of $m)" "${BASH_REMATCH[4]}"
		fi
	done
	if (( PIPESTATUS[0] )); then
		# the batch stopped (a conflict, say): one at a time, to find which
		unknown+=("${known[@]}")
	fi
	done_w=$(( base + count ))
	for p in "${unknown[@]}"; do
		pacman -Q "$p" >/dev/null 2>&1 && continue
		show "Installing $p" "$(describe "$p")"
		pac -S "$p" || fail "$p"
	done
}

other_packages() {
	local entry tag program i=0 n=${#other[@]} aur_done
	aur_done=$(pacman -Qqm 2>/dev/null)
	for entry in "${other[@]}"; do
		tag=${entry%%,*} program=${entry#*,} i=$((i + 1))
		show "$i of $n  ·  $(basename "$program" .git | sed -E 's/-(bin|git)$//')" "$(describe "$program")"
		case $tag in
			A)
				grep -qx "$program" <<< "$aur_done" ||
					as_user "$AURHELPER" -S --needed --noconfirm --answerclean None --answerdiff None \
						--answeredit None --removemake --mflags --nocheck "$program" >>"$LOG" 2>&1 || fail "$program"
				advance 4 ;;
			S)
				local dir=$REPODIR/$program
				pacman -Q "$program" >/dev/null 2>&1 || {
					rm -rf "$dir"
					as_user git clone --depth 1 -q "https://aur.archlinux.org/$program.git" "$dir" >>"$LOG" 2>&1 &&
						(cd "$dir" && as_user makepkg -sif --noconfirm >>"$LOG" 2>&1)
				} || fail "$program"
				advance 4 ;;
			F)
				{ pac -S flatpak &&
					flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >>"$LOG" 2>&1 &&
					flatpak install -y --noninteractive flathub "$program" >>"$LOG" 2>&1; } || fail "$program"
				advance 3 ;;
			G)
				local dir
				dir=$REPODIR/$(basename "$program" .git)
				{ if [ -d "$dir/.git" ]; then as_user git -C "$dir" pull -q --force >>"$LOG" 2>&1
				  else as_user git clone --depth 1 -q "$program" "$dir" >>"$LOG" 2>&1; fi &&
					as_user make -C "$dir" >>"$LOG" 2>&1 && make -C "$dir" install >>"$LOG" 2>&1; } || fail "$program"
				advance 3 ;;
			P)
				{ command -v pipx >/dev/null || pac -S python-pipx; } &&
					as_user pipx install "$program" >>"$LOG" 2>&1 && as_user pipx ensurepath >>"$LOG" 2>&1 || fail "$program"
				advance 3 ;;
			*)
				echo "unknown tag '$tag' for $program" >> "$LOG"; fail "$program (unknown tag $tag)"
				advance 3 ;;
		esac
	done
}

# Every package from the list marked as installed on purpose. One that was on the system already as another
# package's dependency keeps that reason through --needed, so it goes when that package does: pacman -Rns, or
# cleaner's orphans (openssh went with nautilus-gnome-disks, as a dependency of gcr-4)
mark_explicit() {
	local entry names=("${repo[@]}")
	for entry in "${other[@]}"; do
		case ${entry%%,*} in A | S) names+=("${entry#*,}") ;; esac
	done
	# only the installed ones (pacman -D stops at a name it doesn't have: a group, or one that failed)
	mapfile -t names < <(pacman -Qq -- "${names[@]}" 2>/dev/null)
	(( ${#names[@]} )) && pacman -D --asexplicit -- "${names[@]}" >>"$LOG" 2>&1
	return 0
}

install_dotfiles() {
	show "Installing your dotfiles" "$DOTFILES"
	local tmp
	tmp=$(mktemp -d) && chown "$name:$group" "$tmp"
	if as_user git clone --depth 1 --single-branch --no-tags -q --recurse-submodules -b "$BRANCH" "$DOTFILES" "$tmp/d" >>"$LOG" 2>&1; then
		# the repo's own files stay out of your home folder
		rm -rf "$tmp/d/.git" "$tmp/d/README.md" "$tmp/d/LICENSE"
		find "$tmp/d" -name .git -prune -exec rm -rf {} + 2>/dev/null
		as_user cp -rfT "$tmp/d" "$home" >>"$LOG" 2>&1 || fail "copying the dotfiles"
	else
		fail "dotfiles (couldn't clone $DOTFILES)"
	fi
	rm -rf "$tmp"
	advance 2
}

install_wallpapers() {
	show "Downloading the wallpapers" "$WALLPAPERS  →  ~/wallpapers"
	local tmp
	tmp=$(mktemp -d) && chown "$name:$group" "$tmp"
	if as_user git clone --depth 1 --single-branch --no-tags -q "$WALLPAPERS" "$tmp/w" >>"$LOG" 2>&1; then
		rm -rf "$tmp/w/.git" "$tmp/w/README.md" "$tmp/w/LICENSE"
		as_user cp -rfT "$tmp/w" "$home/wallpapers" >>"$LOG" 2>&1 || fail "copying the wallpapers"
	else
		fail "wallpapers (couldn't clone $WALLPAPERS)"
	fi
	rm -rf "$tmp"
	advance 2
}

setup_ssh() {
	# ~/.ssh, your key (never over one you have), and the agent: it keeps the key unlocked once
	# you've typed the passphrase, until you log out
	show "Setting up SSH" "your key, and the agent that remembers its passphrase"
	local d=$home/.ssh unit f wants agent=""
	as_user mkdir -p "$d" && chmod 700 "$d"
	if (( ssh_make )) && [ ! -e "$d/id_ed25519" ] && [ ! -e "$d/id_ed25519.pub" ]; then
		# no terminal (setsid), so ssh-keygen reads the passphrase from the pipe, not the screen
		printf '%s\n%s\n' "$ssh_pass" "$ssh_pass" |
			as_user env SSH_ASKPASS_REQUIRE=never setsid -w ssh-keygen -q -t ed25519 -a 100 \
				-C "$name@$(uname -n)" -f "$d/id_ed25519" >>"$LOG" 2>&1 || fail "SSH key"
	fi
	unset ssh_pass
	# the first time ssh uses the key, the agent keeps it
	[ -e "$d/config" ] || as_user sh -c 'umask 077 && printf "Host *\n\tAddKeysToAgent yes\n" > "$1"' _ "$d/config"
	# openssh's own agent unit, turned on the way 'systemctl --user enable' does it (systemd only: on Artix
	# there are no user units, and ssh asks for the passphrase each time instead)
	if (( systemd )); then
		for unit in ssh-agent.socket ssh-agent.service; do
			f=/usr/lib/systemd/user/$unit
			[ -f "$f" ] || continue
			wants=$(sed -n 's/^WantedBy=[[:space:]]*//p' "$f" | head -n 1)
			wants=${wants%% *}
			case $unit in *.socket) wants=${wants:-sockets.target} ;; *) wants=${wants:-default.target} ;; esac
			as_user mkdir -p "$home/.config/systemd/user/$wants.wants" &&
				as_user ln -sf "$f" "$home/.config/systemd/user/$wants.wants/$unit" && agent=$unit
			break
		done
		[ -n "$agent" ] || fail "the SSH agent (no ssh-agent user unit from openssh)"
	fi
	advance 1
}

configure() {
	show "Setting things up" "the login screen, system settings"
	configure_login
	# no PC speaker beep
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
	# kernel messages (dmesg) readable without sudo
	mkdir -p /etc/sysctl.d
	echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf
	# screen tearing allowed in games (less input lag), for wlroots compositors like mango
	grep -qx "WLR_DRM_NO_ATOMIC=1" /etc/environment 2>/dev/null || echo "WLR_DRM_NO_ATOMIC=1" >> /etc/environment
	# Artix: no systemd to give the machine an id and a dbus session, so they're made here
	if (( ! systemd )); then
		mkdir -p /var/lib/dbus
		[ -s /var/lib/dbus/machine-id ] || dbus-uuidgen > /var/lib/dbus/machine-id 2>/dev/null
		echo 'export $(dbus-launch)' > /etc/profile.d/dbus.sh
	fi
	as_user mkdir -p "$home/.local/share/gnupg" && chmod 700 "$home/.local/share/gnupg"
	advance 2
}

# ly at boot. With an encrypted disk it logs you straight in (the disk's password at boot is the lock);
# without one it asks for your password
configure_login() {
	# (by its package: the program is ly-dm in newer ly, so a 'ly' command can't be looked for)
	pacman -Q ly >/dev/null 2>&1 || { fail "the login screen (ly isn't installed)"; return; }
	mkdir -p /etc/ly
	[ -f "$home/.config/ly/config.ini" ] && cp -f "$home/.config/ly/config.ini" /etc/ly/config.ini
	if [ -f /etc/ly/config.ini ]; then
		sed -i -E "/^[[:space:]]*auto_login_(user|session)[[:space:]]*=/d" /etc/ly/config.ini
		(( encrypted )) && printf "auto_login_user = %s\nauto_login_session = %s\n" "$name" "$SESSION" >> /etc/ly/config.ini
	fi
	# lets ly log in without a password (ly ships this; older versions may not)
	(( encrypted )) && [ ! -f /etc/pam.d/ly-autologin ] && cat > /etc/pam.d/ly-autologin << 'EOF'
#%PAM-1.0

auth       required     pam_permit.so
account    include      login
password   include      login
-session   optional     pam_systemd.so       class=greeter
session    include      login
EOF
	# ly takes over tty1 at the next boot (not now: that would close this session); newer ly is a service per tty
	# (ly@tty1), older ly one service (ly)
	local unit=ly@tty1.service
	[ -e /usr/lib/systemd/system/ly@.service ] || unit=ly.service
	(( systemd )) && systemctl disable getty@tty1.service >>"$LOG" 2>&1
	service_on ly "$unit" || fail "the login screen (turning ly on: do it by hand)"
}

# virt-manager ready to use without root: libvirtd on, you in its group, and the ISOs and VMs folders its own
setup_kvm() {
	show "Setting up virtual machines" "libvirtd, the libvirt group, the ISOs and VMs folders"
	pacman -Q libvirt >/dev/null 2>&1 || { fail "virtual machines (libvirt isn't installed)"; advance 2; return; }
	# libvirt runs its own dnsmasq for the VMs' networks: the system one would hold the same ports
	service_off dnsmasq
	service_on libvirtd || fail "virtual machines (turning libvirtd on)"
	# libvirt's socket open to the libvirt group (you), not just root
	local c=/etc/libvirt/libvirtd.conf q=/etc/libvirt/qemu.conf
	if [ -f "$c" ]; then
		sed -i -E '/^unix_sock_(group|rw_perms)[[:space:]]*=/d' "$c"
		printf 'unix_sock_group = "libvirt"\nunix_sock_rw_perms = "0770"\n' >> "$c"
	fi
	# the VMs run as you, so they can use disks and ISOs in your folders
	if [ -f "$q" ]; then
		sed -i -E '/^(user|group)[[:space:]]*=/d' "$q"
		printf 'user = "%s"\ngroup = "libvirt"\n' "$name" >> "$q"
	fi
	usermod -aG libvirt "$name" || fail "virtual machines (adding you to the libvirt group)"
	libvirt_start
	chown -R "$name:libvirt" "$home/ISOs" "$home/VMs" && chmod -R 770 "$home/ISOs" "$home/VMs" ||
		fail "virtual machines (the ISOs and VMs folders)"
	spice_capslock
	advance 2
}

# libvirtd running now (Whonix is added to it next). It won't start when an old secrets key is in the way (from
# installing over an earlier system): that key is moved aside (secrets-encryption-key.bk) and it's started again
libvirt_up() {
	local i=0
	until virsh -c qemu:///system version >/dev/null 2>&1; do
		i=$((i + 1)); (( i > 15 )) && return 1
		sleep 2
	done
}
libvirt_start() {
	local key=/var/lib/libvirt/secrets/secrets-encryption-key
	if (( systemd )); then systemctl restart libvirtd.service >>"$LOG" 2>&1; else service_start libvirtd; fi
	libvirt_up && return 0
	if [ -f "$key" ]; then
		mv -f "$key" "$key.bk"
		if (( systemd )); then systemctl restart libvirtd.service >>"$LOG" 2>&1; else service_start libvirtd; fi
		libvirt_up && return 0
	fi
	fail "virtual machines (libvirtd didn't start: see $LOG)"
	return 1
}

# Spice sends Caps Lock to a VM twice (a bug in spice). Caps Lock made Esc here on the host, for every keyboard, gets
# round it: 70039 is Caps Lock on any USB or Bluetooth keyboard, 3a on a built-in (PS/2) one
spice_capslock() {
	mkdir -p /etc/udev/hwdb.d
	cat > /etc/udev/hwdb.d/95-keyboard-remap.hwdb << 'EOF'
# Caps Lock is Esc (SHS): spice sends Caps Lock to VMs twice
evdev:input:b0003*
 KEYBOARD_KEY_70039=esc

evdev:input:b0005*
 KEYBOARD_KEY_70039=esc

evdev:atkbd:*
 KEYBOARD_KEY_3a=esc
EOF
	{ if command -v systemd-hwdb >/dev/null; then systemd-hwdb update; else udevadm hwdb --update; fi &&
		udevadm trigger --subsystem-match=input --action=change; } >>"$LOG" 2>&1 ||
		fail "Caps Lock as Esc (the spice fix: works after a reboot)"
}

# Whonix: the latest release, its signature checked against the pinned key, unpacked into ~/VMs (disks, VM and
# network definitions), and added to libvirt by whonix-refresh. The networks on virbr2 and virbr3, as before
setup_whonix() {
	(( whonix )) || return 0
	local v f d=$home/VMs tmp=$home/VMs/.whonix g got
	show "Downloading Whonix" "the latest release: 2 GB, this takes a while"
	v=$(curl -fsSL --max-time 30 "$WHONIX/" | grep -o 'href="[0-9][0-9.]*/"' | grep -o '[0-9][0-9.]*[0-9]' | sort -V | tail -n 1)
	[ -n "$v" ] || { fail "Whonix (couldn't find its latest version at $WHONIX)"; advance 15; return; }
	f=Whonix-LXQt-$v.Intel_AMD64.qcow2.libvirt.xz
	mkdir -p "$tmp"
	if ! curl -fL --retry 3 -C - -o "$tmp/$f" "$WHONIX/$v/$f" >>"$LOG" 2>&1 || ! curl -fsSL -o "$tmp/$f.asc" "$WHONIX/$v/$f.asc"; then
		rm -rf "$tmp"; fail "Whonix (the download didn't finish)"; advance 15; return
	fi
	advance 5
	# signed by Whonix's key, and that key is the one pinned here (a key in a keyring of its own, nothing else in it)
	show "Checking Whonix's signature" "$f"
	g=$(mktemp -d)
	curl -fsSL --max-time 30 "$WHONIX_KEY" | gpg --homedir "$g" --batch --import >>"$LOG" 2>&1
	got=$(gpg --homedir "$g" --batch --with-colons --fingerprint 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
	# the good signature must be made by the pinned key itself (VALIDSIG ends with the signer's primary key), not just
	# by any key the downloaded file happened to contain
	if [ "$got" != "$WHONIX_FPR" ] ||
		! gpg --homedir "$g" --batch --status-fd 1 --verify "$tmp/$f.asc" "$tmp/$f" 2>>"$LOG" |
			grep -q "^\[GNUPG:\] VALIDSIG .* $WHONIX_FPR\$"; then
		rm -rf "$g" "$tmp"; fail "Whonix (its signature didn't check out, so it isn't installed)"; advance 10; return
	fi
	rm -rf "$g"
	show "Unpacking Whonix" "into ~/VMs"
	tar -xSJf "$tmp/$f" -C "$tmp" >>"$LOG" 2>&1 || { rm -rf "$tmp"; fail "Whonix (unpacking it)"; advance 10; return; }
	rm -f "$tmp/$f" "$tmp/$f.asc"
	# you said yes to the licence at the start
	touch "$tmp/WHONIX_BINARY_LICENSE_AGREEMENT_accepted"
	# plain names in ~/VMs: the disks, the VMs, the networks
	mv -f "$tmp"/Whonix-Gateway*.qcow2 "$d/Whonix-Gateway.qcow2" && mv -f "$tmp"/Whonix-Workstation*.qcow2 "$d/Whonix-Workstation.qcow2" &&
		mv -f "$tmp"/Whonix-Gateway*.xml "$d/Whonix-Gateway.xml" && mv -f "$tmp"/Whonix-Workstation*.xml "$d/Whonix-Workstation.xml" ||
		{ rm -rf "$tmp"; fail "Whonix (its files weren't where expected: see $LOG)"; advance 10; return; }
	for g in "$tmp"/[Ww]honix_[Ee]xternal*.xml; do [ -f "$g" ] && mv -f "$g" "$d/Whonix-External.xml"; done
	for g in "$tmp"/[Ww]honix_[Ii]nternal*.xml; do [ -f "$g" ] && mv -f "$g" "$d/Whonix-Internal.xml"; done
	mv -f "$tmp"/WHONIX_BINARY_LICENSE_AGREEMENT* "$d/" 2>/dev/null
	rm -rf "$tmp"
	# the VMs use the disks in ~/VMs; the external and internal networks are virbr2 and virbr3
	sed -i -E "s|<source file=(['\"])[^'\"]*\.qcow2(['\"])|<source file='$d/Whonix-Gateway.qcow2'|" "$d/Whonix-Gateway.xml"
	sed -i -E "s|<source file=(['\"])[^'\"]*\.qcow2(['\"])|<source file='$d/Whonix-Workstation.qcow2'|" "$d/Whonix-Workstation.xml"
	[ -f "$d/Whonix-External.xml" ] && sed -i -E "s|<bridge name=(['\"])[^'\"]*(['\"])|<bridge name='virbr2'|" "$d/Whonix-External.xml"
	[ -f "$d/Whonix-Internal.xml" ] && sed -i -E "s|<bridge name=(['\"])[^'\"]*(['\"])|<bridge name='virbr3'|" "$d/Whonix-Internal.xml"
	chown -R "$name:libvirt" "$d" && chmod -R 770 "$d"
	install_whonix_refresh
	show "Adding Whonix to virt-manager" "the Gateway, the Workstation and their networks"
	WHONIX_DIR=$d /usr/local/bin/whonix-refresh -y >>"$LOG" 2>&1 || fail "Whonix (adding it to libvirt: run whonix-refresh)"
	advance 5
}

# whonix-refresh: your old refreshvms, as a command. Takes the Whonix VMs and their networks out of libvirt and puts
# them back from ~/VMs (the disks stay as they are)
install_whonix_refresh() {
	cat > /usr/local/bin/whonix-refresh << 'EOF'
#!/bin/sh
# whonix-refresh: takes the Whonix VMs and their networks out of libvirt, then puts them back from ~/VMs
# (Whonix-Gateway.xml, Whonix-Workstation.xml, Whonix-External.xml, Whonix-Internal.xml). Their disks stay as
# they are. -y: no question in between
d=${WHONIX_DIR:-$HOME/VMs}
v() { virsh -c qemu:///system "$@"; }
for vm in Whonix-Gateway Whonix-Workstation; do v destroy "$vm"; v undefine "$vm"; done >/dev/null 2>&1
for n in Whonix-External Whonix-Internal; do v net-destroy "$n"; v net-undefine "$n"; done >/dev/null 2>&1
echo "[+] VMs removed"
[ "$1" = -y ] || { printf 'Add them again? (Ctrl+C stops) '; read -r _; }
for n in External Internal; do
	[ -f "$d/Whonix-$n.xml" ] || continue
	v net-define "$d/Whonix-$n.xml" && v net-autostart "Whonix-$n" && v net-start "Whonix-$n" || exit 1
done
v define "$d/Whonix-Gateway.xml" && v define "$d/Whonix-Workstation.xml" || exit 1
echo "[+] VMs added: open them in virt-manager"
EOF
	chmod 755 /usr/local/bin/whonix-refresh
}

# DNSCrypt: every name lookup encrypted, and anonymized through relays, so neither your internet provider nor the
# DNS server sees which sites you look up together with your address. Last, as it changes where lookups go
setup_dns() {
	show "Encrypting DNS" "dnscrypt-proxy, through anonymizing relays"
	local t=/etc/dnscrypt-proxy/dnscrypt-proxy.toml
	pac -S dnscrypt-proxy && [ -f "$t" ] || { fail "encrypted DNS (dnscrypt-proxy)"; advance 2; return; }
	# on 127.0.0.1:53 itself (the service, not the socket); in [anonymized_dns]: any server through any relay, and the
	# servers that can't be anonymized (DoH) left out
	awk '
		/^\[/ { sec = $0 }
		sec == "" && /^listen_addresses[[:space:]]*=/ { print "listen_addresses = [\x27127.0.0.1:53\x27]"; next }
		sec == "[anonymized_dns]" && /^(routes|skip_incompatible)[[:space:]]*=/ { next }
		{ print }
		/^\[anonymized_dns\]/ { print "routes = [ { server_name = \x27*\x27, via = [\x27*\x27] } ]"; print "skip_incompatible = true" }
	' "$t" > "$t.new" && mv -f "$t.new" "$t"
	grep -q '^listen_addresses' "$t" || sed -i "1i listen_addresses = ['127.0.0.1:53']" "$t"
	# the old resolv.conf kept (its contents, also when it's a link to systemd-resolved's file), before
	# systemd-resolved is turned off below and that file goes away
	[ -e /etc/resolv.conf ] && [ ! -e /etc/resolv.conf.bak ] && cp -L /etc/resolv.conf /etc/resolv.conf.bak
	# nothing else answering on port 53 or writing resolv.conf
	(( systemd )) && systemctl is-enabled -q systemd-resolved 2>/dev/null && service_off systemd-resolved
	[ -d /etc/NetworkManager ] && mkdir -p /etc/NetworkManager/conf.d &&
		printf '[main]\ndns=none\n' > /etc/NetworkManager/conf.d/dns.conf
	# NetworkManager reads that only when it (re)loads its settings: still running on the old ones, it rewrites
	# resolv.conf as systemd-resolved goes, an empty one over ours below. The computer itself gets by (with no
	# nameserver it asks 127.0.0.1 anyway), but the VMs' DNS doesn't: libvirt's dnsmasq takes its servers from
	# resolv.conf, finds none, and refuses every lookup
	command -v nmcli >/dev/null 2>&1 && nmcli general reload conf >>"$LOG" 2>&1
	[ -f /etc/dhcpcd.conf ] && ! grep -qx 'nohook resolv.conf' /etc/dhcpcd.conf && echo 'nohook resolv.conf' >> /etc/dhcpcd.conf
	(( systemd )) && systemctl disable dnscrypt-proxy.socket >>"$LOG" 2>&1
	service_on dnscrypt-proxy || { fail "encrypted DNS (turning dnscrypt-proxy on)"; advance 2; return; }
	service_start dnscrypt-proxy
	# lookups go to it
	[ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
	printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf
	local i=0
	# and still there once it's up (written again if anything replaced it meanwhile)
	until grep -qx 'nameserver 127.0.0.1' /etc/resolv.conf || printf 'nameserver 127.0.0.1\noptions edns0\n' > /etc/resolv.conf
		dnscrypt-proxy -config "$t" -resolve archlinux.org >>"$LOG" 2>&1 && ss -lun 2>/dev/null | grep -q '127.0.0.1:53 ' &&
		sleep 2 && grep -qx 'nameserver 127.0.0.1' /etc/resolv.conf; do
		i=$((i + 1)); (( i > 15 )) && { fail "encrypted DNS (dnscrypt-proxy didn't start yet: it should after the reboot)"; break; }
		sleep 2
	done
	advance 2
}

finish() {
	# what only shs does, then the dotfiles' own setup and clean-up
	local timer up=$home/.local/bin/update
	# Glide's Pywalfox helper (wallpaper colours)
	command -v pywalfox >/dev/null 2>&1 &&
		as_user pywalfox install --manifest-path "$home/.glide-browser/native-messaging-hosts" >>"$LOG" 2>&1
	# your timers (systemctl --user can't run from here): what 'enable' does, by hand (a backup timer, say)
	if (( systemd )); then
		for timer in "$home"/.config/systemd/user/*.timer; do
			[ -f "$timer" ] || continue
			as_user mkdir -p "${timer%/*}/timers.target.wants"
			as_user ln -sf "../${timer##*/}" "${timer%/*}/timers.target.wants/${timer##*/}"
		done
	fi
	advance 2

	if [ -x "$up" ]; then
		show "Running update" "system settings, plugins, clean-up; it takes a while"
		as_user "$up" >>"$LOG" 2>&1 || fail "update (some steps: run update again after logging in)"
	else
		# dotfiles without update: their sys-setup and cleaner on their own
		if [ -x "$home/.local/bin/sys-setup" ]; then
			show "Running sys-setup" "the rest of the system settings"
			as_user "$home/.local/bin/sys-setup" >>"$LOG" 2>&1 || fail "sys-setup (some steps: run sys-setup again after logging in)"
		fi
		show "Cleaning up" "orphaned packages, package caches, build leftovers"
		if [ -x "$home/.local/bin/cleaner" ]; then
			as_user "$home/.local/bin/cleaner" >>"$LOG" 2>&1 || fail "cleaner (some steps)"
		else
			# no cleaner in the dotfiles: the basics here
			local orphans
			orphans=$(pacman -Qtdq 2>/dev/null)
			[ -n "$orphans" ] && pacman --noconfirm -Rns $orphans >>"$LOG" 2>&1
			as_user "$AURHELPER" -Scc --noconfirm >>"$LOG" 2>&1
			rm -rf /var/cache/pacman/pkg/download-*
		fi
	fi
	advance 10
}

configure_sudo() {
	# replaces the temporary no-password rule: password for sudo again, except these
	# (no passwordless mount / umount: those would let anyone in wheel become root)
	echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/00-wheel-sudo
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: \
/usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,\
/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,\
/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm" > /etc/sudoers.d/01-passwordless-cmds
	echo "Defaults editor=/usr/bin/nvim" > /etc/sudoers.d/02-visudo-editor
	chmod 440 /etc/sudoers.d/0[012]-*
	rm -f /etc/sudoers.d/shs-temp
}

install_all() {
	progress_init
	update_system || return
	setup_user || return
	aur_helper
	repo_packages
	other_packages
	mark_explicit
	install_dotfiles
	install_wallpapers
	setup_ssh
	configure
	setup_kvm
	setup_whonix
	finish
	setup_dns
	done_w=$total_w
	printf 'XXX\n100\nDone\nXXX\n' >&3
}


# MAIN

preflight
trap 'rm -f /etc/sudoers.d/shs-temp; rm -rf "$WORK"; [ -t 0 ] && stty sane' EXIT
trap 'exit 1' HUP INT QUIT TERM

step_line 1 "a few questions"
welcome || die "cancelled."
get_user
get_ssh_pass
ask_whonix
get_progs
plan
summary || die "cancelled."

step_line 2 "installing"
: > "$WORK/failed"
{ install_all 3>&1 1>>"$LOG" 2>&1 </dev/null; } | wt --title "Installing" --gauge "Starting...\n\n " 12 74 0
unset ssh_pass
configure_sudo
[ -n "${home:-}" ] || home=$(getent passwd "$name" | cut -d: -f6)

step_line 3 "done"
mapfile -t failed < <(sort -u "$WORK/failed")
if grep -qx "system update" "$WORK/failed"; then
	msg="The system update failed, so nothing else was installed (installing onto a half-updated system can break it).\n\nWhy is in $LOG (often a mirror that's down, or a package conflict: run  sudo pacman -Syu  to see it). Fix that, then run shs again."
	if (( yes )); then clear; printf '%b\n' "$msg"; else wt --title "Stopped" --msgbox "$msg" 13 76; clear; fi
	exit 1
fi
if (( ${#failed[@]} )); then
	result="Done, but these didn't install:\n\n$(printf '  %s\\n' "${failed[@]}")\nWhy is in $LOG. Install them later with: yay -S NAME"
	height=$(( 14 + ${#failed[@]} ))
else
	result="Everything installed."
	height=12
fi
# the public key, to paste into GitHub (Settings, SSH and GPG keys)
pub=$home/.ssh/id_ed25519.pub
if [ -f "$pub" ]; then
	result+="\n\nYour SSH key is ~/.ssh/id_ed25519.\nFor GitHub, paste its public key (cat ~/.ssh/id_ed25519.pub):\n\n$(cat "$pub")\n\nFingerprint: $(ssh-keygen -lf "$pub" | cut -d' ' -f2)"
	height=$(( height + 9 ))
fi
if (( encrypted )); then after="After a reboot you go straight into your desktop as '$name', once the disk is unlocked."
else after="After a reboot, log in as '$name' at the login screen."; fi
# scrolling text takes the keys (Enter wouldn't press "Reboot now"): only when it doesn't fit the screen
rows=$(tput lines 2>/dev/null || echo 24) scroll=()
(( height > rows - 2 )) && { height=$(( rows - 2 )); scroll=(--scrolltext); }
if (( yes )); then
	clear
	printf '%b\n\n%s\n' "$result" "$after"
elif wt --title "All done!" "${scroll[@]}" --yes-button "Reboot now" --no-button "Later" --yesno \
	"$result\n\n$after\n\n-Sekigetsu" "$height" 78; then
	# what the install left running as you (gpg agents from yay, helpers from the dotfiles' setup…) is in this
	# login's session, and the shutdown hangs on it behind a black screen: everything of yours stopped first (a login
	# of yours on this tty too, so its hangup mustn't stop shs before the reboot)
	clear
	trap '' HUP
	pkill -TERM -u "$name"; sleep 2; pkill -KILL -u "$name"
	rm -rf "$WORK"
	exec reboot
else
	clear
fi
