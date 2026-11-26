# Sekigetsu's Host Setup

## Installation:

On a fresh Arch Linux install, log in as the user you made while installing and run:

```
sudo pacman -S git
git clone https://github.com/sekigetsu01/SHS.git
cd SHS/static
sudo sh shs.sh
```

If that user can't use sudo yet (a hand-made install has no sudo until SHS sets it up), do the same as root:
`pacman -S git`, clone it the same way, and run `sh shs.sh`; it finds your user by itself.

SHS sets up that user: no new username or password to enter (if there's no user yet, it makes one).
It asks a few things at the start (h and l, or the arrows, pick a button; y and n answer yes or no), shows what it's about to
do, and then runs by itself with a progress bar and the time left. When it's done, it lists anything
that didn't install.

It also asks for a passphrase for a new SSH key (twice; Skip makes none). The passphrase stays in
memory only. The key is `~/.ssh/id_ed25519` (ed25519), never made over one you already have, and
the end screen shows its public key for GitHub (`cat ~/.ssh/id_ed25519.pub`). The dotfiles turn on
openssh's `ssh-agent` and their `sys-setup` adds `AddKeysToAgent yes` to `~/.ssh/config`, so you type
the passphrase once per login. With `-y` no key is made.

Before anything else it checks that this is Arch Linux with systemd (the dotfiles' `update`,
`sys-setup` and timers need it, so Artix isn't supported), that there's internet and at least
20 GB free, and that pacman isn't busy, and stops with a clear message if not.

Options:

```
sudo sh shs.sh -y          no questions: installs everything
sudo sh shs.sh -u NAME     set up NAME (when there's more than one user)
```

## What is SHS?

SHS is a script that autoinstalls and autoconfigures a minimal terminal-and-vim-based
Arch Linux desktop on Wayland, made to be the host your virtual machines run on: QEMU, libvirt
and virt-manager come with it. Everything it installs is free software.

It also installs the real-time kernel (`linux-rt` and `linux-rt-headers`, from the Arch repos) next to the one
you have. It isn't added to your boot menu: with GRUB run `sudo grub-mkconfig -o /boot/grub/grub.cfg`, with
systemd-boot add an entry for it. To leave it out, delete those two lines from `progs.csv`.

SHS is inspired by [LARBS](https://github.com/LukeSmithxyz/LARBS).

## Customization

By default, SHS uses the programs [here in progs.csv](static/progs.csv) and installs
[my dotfiles repo here](https://github.com/sekigetsu01/hostrice), and puts
[my wallpapers](https://github.com/sekigetsu01/wallpapers) in `~/wallpapers` (where `wallpaper` picks
from). Once the dotfiles are in place it runs their `update` (sys-setup, plugins, then its clean-up).
Run again, it copies the dotfiles over yours again, except the few files their scripts change (`KEEP` in
`shs.sh`: `~/.config/times.conf`, the timers' `times.conf`, kp's and the clicker's config): those it only adds when missing.

### The `progs.csv` list

SHS will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`. SHS uses the `progs.csv` next to
`shs.sh`, so your edits are used straight away (the copy on GitHub only if there isn't one).

The first column is a "tag" that determines how the program is installed, ""
(blank) for the main repository, or `A` for installation via the AUR.

The second column is the name of the program in the repository, and the third column is a description
that describes the program.
During installation, SHS shows it under the program's name. It also doubles as documentation
for people who read the CSV and want to install my dotfiles manually.

SHS installs every repo program (blank tag) first, all in one pacman run, then the others one by one, from the
top of the list to the bottom. If you include commas in your program
descriptions, put double quotes around the whole description.

Take a program out of the list and the next run removes it, with the dependencies only it needed
(`pacman -Rs`). SHS keeps what it installed in `/var/lib/shs/packages`, and only ever removes names from there,
so programs you installed yourself are left alone. One that something else still needs stays, marked as a dependency.
The final message lists what was removed. A system set up by an SHS from before this has no such file: its first run
only writes it; programs dropped before then are listed by name in `DROPPED` (top of `shs.sh`) and removed the same way.

### The script itself

The main work is done by `install_all`, which runs under the progress bar. It updates the
system first, then
installs every repo package in one pacman run (much faster than one at a time; any name pacman
doesn't know is tried on its own, so one bad name doesn't stop the rest), then goes through the
other programs one by one, choosing how to install each from its tag (`other_packages`). New methods
of installation and tags go there.

It also makes the folders `Downloads`, `Documents`, `Passwords`, `ISOs`, `VMs` and `github`, turns
off the PC speaker beep, lets you read kernel messages (`dmesg`) without sudo, and allows screen
tearing in games (`WLR_DRM_NO_ATOMIC=1`).

Everything the installs print goes to `/var/log/shs.log`. If anything fails to install,
SHS lists it at the end, and the log says why.

Programs from the AUR can only be built by a non-root user, so SHS lets your user use `sudo`
without a password while it runs. At the end that's removed, leaving only exactly `sudo pacman -Syu`
(nothing added to it) without a password. `update` still asks for yours once, at the start.
The VPN (`Super+u`) starts without one too: SHS runs the dotfiles' `vpn-install`, which installs the VPN's
root half (`/usr/local/lib/vpn-root`) and a sudo rule for exactly that.

## Login screen

SHS sets this up itself: it copies `~/.config/ly/config.ini` from the dotfiles to
`/etc/ly/config.ini` and turns ly on (`ly@tty1.service`). If your disk is encrypted, it also logs you in automatically: you've already typed
the disk's password at boot, so a second password is a waste of time (not when the disk unlocks itself,
with a TPM or a key file: then nobody types one, so ly asks). Without an encrypted disk,
ly asks for your password.

## Network

The wifi menu (`Super+F5`) and the network in the bar use NetworkManager. SHS turns it on (from the next boot)
when nothing else runs your network. If iwd, systemd-networkd, dhcpcd, connman, netctl or wpa_supplicant does
(also per interface or profile, like `dhcpcd@enp1s0`), it's left as it is (switching could leave you without
internet, or with two DHCP clients) and the end screen says so: switch by hand if you want the menu.

## KVM

SHS sets virt-manager up itself, so it works without root:

- `libvirtd` is turned on, and the system's own
  `dnsmasq` is turned off, since libvirt runs its own for the VMs' networks.
- You're added to the `libvirt` group (it takes effect at the next login, so after the reboot). That's
  what lets you use libvirt without root: the libvirt package's polkit rule lets the `libvirt` group in.
- `/etc/libvirt/qemu.conf` gets `user = "you"` and `group = "libvirt"`, so VMs run as you and can use
  disks and ISOs in your folders.
- `/etc/libvirt/libvirtd.conf` gets `unix_sock_group = "libvirt"` and `unix_sock_rw_perms = "0770"`.
  These only count when libvirtd runs without its systemd sockets: on Arch the sockets start it, libvirt
  ignores these two lines, and the polkit rule above does the job.
- libvirt's `default` network (NAT on `virbr0`) is started, and starts at every boot, so a new VM has a
  network straight away. Only on a fresh setup, where it's the only network: if you already have networks
  of your own (they may use the same bridge or addresses), it's left as it is.
- `~/ISOs` and `~/VMs` belong to you and the `libvirt` group (`770`).
- The dark GTK theme virt-manager uses (Adwaita-dark, from gnome-themes-extra) is switched on by the dotfiles.

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
  to leave it alone (dhcpcd is restarted so it takes that in straight away).
- The service is turned on and started straight away.
- Your VMs' lookups go through it too: libvirt's own DNS asks the host.

To change servers or relays, edit that file and restart it: `sudo systemctl restart dnscrypt-proxy`.

## Caps Lock in VMs (spice bug)

Spice sends Caps Lock to a VM twice, so it switches on and straight back off: annoying for vim and
in general. The workaround is on the host: Caps Lock is Esc there, so the bug never happens.

SHS writes `/etc/udev/hwdb.d/95-keyboard-remap.hwdb`, which makes Caps Lock Esc on every keyboard:
any USB, Bluetooth or I2C one (Caps Lock is `70039` on all of them) and a built-in PS/2 one (`3a`,
what most laptops' keyboards are). It goes by how the keyboard is connected, not which keyboard it
is, so there's nothing to look up with `evtest`, and a keyboard you plug in later is covered too. It takes
effect straight away (`systemd-hwdb update` and `udevadm trigger`). To check:
`sudo evtest`, pick the keyboard and press Caps Lock: it should say `KEY_ESC`.

## Whonix install

Click [here](https://www.whonix.org/wiki/KVM) to download Whonix.

```
tar -xvf Whonix-* -C ~/VMs
```
```
cd ~/VMs
```
```
touch WHONIX_BINARY_LICENSE_AGREEMENT_accepted
```
```
mv Whonix-Workstation....qcow2 Whonix-Workstation.qcow2
mv Whonix-Gateway....qcow2 Whonix-Gateway.qcow2
```
```
nvim Whonix-Gateway.xml
```
```
nvim Whonix-Workstation.xml
```

Change source to:
```
/home/user/VMs/Whonix-Gateway.qcow2
```
```
/home/user/VMs/Whonix-Workstation.qcow2
```

Change the network virbr for each network.xml, external and internal to virbr2 and virbr3 respectively.

```
nvim refreshvms
```
```
#!/bin/bash

#remove VMs

virsh -c qemu:///system destroy Whonix-Gateway
virsh -c qemu:///system destroy Whonix-Workstation
virsh -c qemu:///system undefine Whonix-Gateway
virsh -c qemu:///system undefine Whonix-Workstation
virsh -c qemu:///system net-destroy Whonix-External
virsh -c qemu:///system net-destroy Whonix-Internal
virsh -c qemu:///system net-undefine Whonix-External
virsh -c qemu:///system net-undefine Whonix-Internal

echo '[+] VMs removed, re-install them ? (ctrl+c to exit)'
read

#install VMs

virsh -c qemu:///system net-define Whonix_external*.xml
virsh -c qemu:///system net-define Whonix_internal*.xml
virsh -c qemu:///system net-autostart Whonix-External
virsh -c qemu:///system net-start Whonix-External
virsh -c qemu:///system net-autostart Whonix-Internal
virsh -c qemu:///system net-start Whonix-Internal
virsh -c qemu:///system define Whonix-Gateway.xml
virsh -c qemu:///system define Whonix-Workstation.xml
```
```
sudo sh refreshvms
```

## libvirt's secrets key

If you install SHS over an earlier system, an old `/var/lib/libvirt/secrets/secrets-encryption-key`
can stop libvirtd from starting. SHS checks: if libvirtd won't start and that key is there, it moves
it aside (`secrets-encryption-key.bk`) and starts libvirtd again.

## Manual setup (if something fails)

The same things SHS sets up, done by hand, in case a step of `shs.sh` fails.

### KVM


#### Virt-Manager

```
sudo systemctl enable --now libvirtd
```
```
sudo systemctl disable --now dnsmasq
```
```
sudo nvim /etc/libvirt/libvirtd.conf
```
```
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
```
```
sudo nvim /etc/libvirt/qemu.conf
```
```
group = "libvirt"
user = "user"
```
```
sudo usermod -a -G libvirt $(whoami)
```
```
newgrp libvirt
```
```
systemctl restart libvirtd.service
```
```
gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
```
```
sudo chmod 770 -R ISOs VMs
```
```
sudo chown user:libvirt -R ISOs VMs
```


### DNS Crypt

```
sudo pacman -S dnscrypt-proxy
```
```
sudo nvim /etc/dnscrypt-proxy/dnscrypt-proxy.toml
```
At the top, set:
```
listen_addresses = ['127.0.0.1:53']
```
and under `[anonymized_dns]`:
```
routes = [ { server_name = '*', via = ['*'] } ]
skip_incompatible = true
```
Stop NetworkManager (and dhcpcd, if you use it) from writing `/etc/resolv.conf`:
```
sudo mkdir -p /etc/NetworkManager/conf.d
printf '[main]\ndns=none\n' | sudo tee /etc/NetworkManager/conf.d/dns.conf
sudo nmcli general reload conf
```
```
echo 'nohook resolv.conf' | sudo tee -a /etc/dhcpcd.conf
```
If systemd-resolved is on, turn it off:
```
sudo systemctl disable --now systemd-resolved
```
Turn dnscrypt-proxy on (the service, not its socket):
```
sudo systemctl disable dnscrypt-proxy.socket
```
```
sudo systemctl enable --now dnscrypt-proxy.service
```
Point the system at it, keeping the old file:
```
sudo cp -L /etc/resolv.conf /etc/resolv.conf.bak
```
```
sudo rm /etc/resolv.conf
```
```
sudo nvim /etc/resolv.conf
```
```
nameserver 127.0.0.1
options edns0
```
Check it answers:
```
dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml -resolve archlinux.org
```

### Spice bug workaround

You may notice without this that in your vm's, the caps lock key double presses.
This is a bug in spice that hasn't been fixed, but there is a workaround is you do the
following on your host OS.

First, we need the scan code from our CapsLock. To get it run: sudo evtest select your keyboard, and then press the CapsLock key. My output is:
```
(...), type 4 (EV_MSC), code 4 (MSC_SCAN), value 70039
(...), type 1 (EV_KEY), code 58 (KEY_CAPSLOCK), value 1
```

What we need from here is value 70039 after (MSC_SCAN), your scancode may be different.
We also need our device id, to get it run:
`cat /sys/class/input/event4/device/modalias`. (You need to replace event4 with your keyboard /dev/input/event* number. You can find it in the output of the evtest command you run before, at the selection of input device) My output is:
```
input:b0003v2F68p0082e0110-e0,1,4,11,14,k71,72,73,74,75,77,79,7A,7B,7C,7D,7E,7F,80,81,82,83,84,85,86,87,88,89,8A,B3,B4,B7,B8,B9,BA,BB,BC,BD,BE,BF,C0,C1,C2,F0,ram4,l0,1,2,3,4,sfw
```

what we need from here is b0003v2F68p0082*.
Create a file `/etc/udev/hwdb.d/95-keyboard-remap.hwdb` with the following content:
```
evdev:input:b0003v2F68p0082*
 KEYBOARD_KEY_70039=esc
```

You need to replace your keyboard key code and device id to match yours.
Finally update hwdb:
```
sudo systemd-hwdb update
```
```
sudo udevadm trigger /dev/input/event2
```
(replace event2 according to the event number on your device.)
No reboot is required. After doing this, check again with sudo evtest if your caps lock key is recognized as KEY_CAPSLOCK or KEY_ESC. If it's KEY_ESC, you won't have the double-sent CapsLock key to the guest. If it's still KEY_CAPSLOCK, you may have wrong values for the scan code or device id, check them again.

### Encryption Key Libvirt Issue when reusing SHS

```
sudo mv -v /var/lib/libvirt/secrets/secrets-encryption-key /var/lib/libvirt/secrets/secrets-encryption-key.bk
```

```
sudo systemctl restart libvirtd
```


### Autologin

copy ~/.config/ly/config.ini to /etc/ly/config.ini

```
sudo systemctl enable ly@tty1.service
```
```
sudo systemctl restart ly@tty1.service
```
