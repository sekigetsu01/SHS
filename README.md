# Sekigetsu's Host Setup

## Installation:

On a fresh Arch Linux (or Artix) install, log in as the user you made while installing and run:

```
git clone https://github.com/sekigetsu01/SHS.git
cd SHS/static
sudo sh shs.sh
```

SHS sets up that user: no new username or password to enter (if there's no user yet, it makes one).
It asks a few things at the start (h and l, or the arrows, pick a button), shows what it's about to
do, and then runs by itself with a progress bar and the time left. When it's done, it lists anything
that didn't install.

It also asks for a passphrase for a new SSH key (twice; Skip makes none). The passphrase stays in
memory only. The key is `~/.ssh/id_ed25519` (ed25519), never made over one you already have, and
the end screen shows its public key for GitHub (`cat ~/.ssh/id_ed25519.pub`). `~/.ssh/config` gets
`AddKeysToAgent yes` (if you have no config yet), and on Arch openssh's `ssh-agent` user unit is
turned on, so you type the passphrase once per login. With `-y` no key is made.

Before anything else it checks that this is Arch Linux or Artix, that there's internet and at least
20 GB free, and that pacman isn't busy, and stops with a clear message if not.

Options:

```
sudo sh shs.sh -y          no questions: installs everything but Whonix (its licence needs your yes)
sudo sh shs.sh -u NAME     set up NAME (when there's more than one user)
```

## What is SHS?

SHS is a script that autoinstalls and autoconfigures a minimal terminal-and-vim-based
Arch Linux desktop on Wayland, made to be the host your virtual machines run on: QEMU, libvirt
and virt-manager come with it. Everything it installs is free software.
SHS is inspired by [LARBS](https://github.com/LukeSmithxyz/LARBS).

## Customization

By default, SHS uses the programs [here in progs.csv](static/progs.csv) and installs
[my dotfiles repo here](https://github.com/sekigetsu01/hostrice), and puts
[my wallpapers](https://github.com/sekigetsu01/wallpapers) in `~/wallpapers` (where `wallpaper` picks
from). Once the dotfiles are in place it runs their `update` if they have one, else their `sys-setup`
and `cleaner`.

### The `progs.csv` list

SHS will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`. SHS uses the `progs.csv` next to
`shs.sh`, so your edits are used straight away (the copy on GitHub only if there isn't one).

The first column is a "tag" that determines how the program is installed, ""
(blank) for the main repository, `F` to install a flatpak, `A` for installation
via the AUR, `S` to build an AUR package by hand, `P` to install via pipx or `G` if the program
is a git repository that is meant to be `make && sudo make install`ed.

The second column is the name of the program in the repository, or the link to
the git repository, and the third column is a description that describes the program.
During installation, SHS shows it under the program's name. It also doubles as documentation
for people who read the CSV and want to install my dotfiles manually.

SHS installs from the top to the bottom. If you include commas in your program
descriptions, put double quotes around the whole description.

### The script itself

The main work is done by `install_all`, which runs under the progress bar. It updates the
system first (on Artix, after adding the Arch repos through `artix-archlinux-support`), then
installs every repo package in one pacman run (much faster than one at a time; any name pacman
doesn't know is tried on its own, so one bad name doesn't stop the rest), then goes through the
other programs one by one, choosing how to install each from its tag (`other_packages`). You can
add new methods of installation and tags there.

It also makes the folders `Downloads`, `Documents`, `Passwords`, `ISOs`, `VMs` and `github`, turns
off the PC speaker beep, lets you read kernel messages (`dmesg`) without sudo, and allows screen
tearing in games (`WLR_DRM_NO_ATOMIC=1`). On Artix it keeps the clock right with ntp and gives the
machine a dbus id and session (systemd does both on Arch).

Everything the installs print goes to `/var/log/shs.log`. If anything fails to install,
SHS lists it at the end, and the log says why.

Programs from the AUR can only be built by a non-root user, so SHS lets your user use `sudo`
without a password while it runs. At the end that's removed, leaving only a few basic sudo
commands without a password (`shutdown`, `reboot`, `systemctl suspend`, `loadkeys`, `pacman -Syu`).

## Login screen

SHS sets this up itself: it copies `~/.config/ly/config.ini` from the dotfiles to
`/etc/ly/config.ini` and turns ly on (`ly@tty1.service` on Arch; on Artix, ly's runit, OpenRC or
dinit service). If your disk is encrypted, it also logs you in automatically: you've already typed
the disk's password at boot, so a second password is a waste of time. Without an encrypted disk,
ly asks for your password.

## KVM

SHS sets virt-manager up itself, so it works without root:

- `libvirtd` is turned on (on Artix, its runit, OpenRC or dinit service), and the system's own
  `dnsmasq` is turned off, since libvirt runs its own for the VMs' networks.
- `/etc/libvirt/libvirtd.conf` gets `unix_sock_group = "libvirt"` and `unix_sock_rw_perms = "0770"`,
  and `/etc/libvirt/qemu.conf` gets `user = "you"` and `group = "libvirt"`, so VMs run as you and
  can use disks and ISOs in your folders.
- You're added to the `libvirt` group (it takes effect at the next login, so after the reboot).
- `~/ISOs` and `~/VMs` belong to you and the `libvirt` group (`770`).
- The dark GTK theme virt-manager uses (Adwaita-dark) comes with the dotfiles.

## Encrypted DNS

SHS sets up [DNSCrypt](https://github.com/DNSCrypt/dnscrypt-proxy) (`dnscrypt-proxy` from the Arch
repos, so pacman keeps it up to date): every name lookup is encrypted, and goes through an
anonymizing relay, so your internet provider can't see which sites you look up, and the DNS server
doesn't see your address.

- `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`: it listens on `127.0.0.1:53`, and `[anonymized_dns]`
  gets `routes = [ { server_name = '*', via = ['*'] } ]` (any server, through any relay) and
  `skip_incompatible = true` (servers that can't be anonymized are left out).
- `/etc/resolv.conf` is `nameserver 127.0.0.1` and `options edns0` (the old one is kept as
  `/etc/resolv.conf.bak`). NetworkManager, dhcpcd and systemd-resolved, if you have them, are told
  to leave it alone.
- The service is turned on (on Artix, its runit, OpenRC or dinit service) and started straight away.
- Your VMs' lookups go through it too: libvirt's own DNS asks the host.

To change servers or relays, edit that file and restart it: `sudo systemctl restart dnscrypt-proxy`.

## Caps Lock in VMs (spice bug)

Spice sends Caps Lock to a VM twice, so it switches on and straight back off: annoying for vim and
in general. The workaround is on the host: Caps Lock is Esc there, so the bug never happens.

SHS writes `/etc/udev/hwdb.d/95-keyboard-remap.hwdb`, which makes Caps Lock Esc on every keyboard:
any USB or Bluetooth one (Caps Lock is `70039` on all of them) and a built-in laptop one (`3a`). So
there's nothing to look up with `evtest`, and a keyboard you plug in later is covered too. It takes
effect straight away (`systemd-hwdb update` and `udevadm trigger`). To check:
`sudo evtest`, pick the keyboard and press Caps Lock: it should say `KEY_ESC`.

## Whonix

SHS asks at the start whether to install [Whonix](https://www.whonix.org/wiki/KVM): two VMs, a
Gateway that runs Tor and a Workstation whose every connection goes through it. Saying yes means
you accept [Whonix's licence](https://www.whonix.org/wiki/License_Agreement). If you do, SHS:

- downloads the latest release (the LXQt desktop one, about 2 GB) and checks its signature against
  Whonix's signing key, pinned in the script (`916B 8D99 C38E AF5E 8ADC 7A2A 8D66 066A 2EEA CCDA`).
  If the signature doesn't check out, nothing is installed.
- unpacks it into `~/VMs` under plain names: `Whonix-Gateway.qcow2`, `Whonix-Workstation.qcow2`
  and their `.xml` files, plus `Whonix-External.xml` and `Whonix-Internal.xml` for the networks.
- points the VMs at those disks, and puts the external and internal networks on `virbr2` and
  `virbr3`.
- adds them all to libvirt, so they're in virt-manager after the reboot.

`whonix-refresh` takes the Whonix VMs and their networks out of libvirt and puts them back from
`~/VMs` (the disks stay as they are), asking in between; `whonix-refresh -y` doesn't ask. Use it
after editing their `.xml` files, or if they get into a mess.

## libvirt's secrets key

If you install SHS over an earlier system, an old `/var/lib/libvirt/secrets/secrets-encryption-key`
can stop libvirtd from starting. SHS checks: if libvirtd won't start and that key is there, it moves
it aside (`secrets-encryption-key.bk`) and starts libvirtd again.
