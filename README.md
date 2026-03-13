# Sekigetsu's Host Setup

## Installation:

On an Arch-based distribution as root, run the following:

```
git clone https://github.com/sekigetsu01/SHS.git
cd SHS/static
sh shs.sh
```

## What is SHS?

SHS is a script that autoinstalls and autoconfigures my host operating
system. SHS is inspired by [LARBS](https://github.com/LukeSmithxyz/LARBS).

It can be run on a fresh install of Arch Linux and provides you
with an almost fully configured host operating system. It has all
the necessary software installed, virtualisation setup and also has some
gaming optimization.

## When use SHS over SWAI?

Both SHS and SWAI are excellent systems, they just have different uses. I
suggest using SWAI in the virtual machines for your workflow and to make use
of compartmentalization for privacy and productivity, since you likely have different
workflows for different activities. However, for your host operating system, SHS
is optimal and pairs nicely with SWAI given the similarity. Overall, use SHS for your
host operating system and SWAI for Arch VMs inside.

## Customization

By default, SHS uses the programs [here in progs.csv](static/progs.csv) and installs
[my dotfiles repo here](https://github.com/sekigetsu01/hostrice),
but you can easily change this by either modifying the default variables at the
beginning of the script or giving the script one of these options:

- `-r`: custom dotfiles repository (URL)
- `-p`: custom programs list/dependencies (local file or URL)
- `-a`: a custom AUR helper (must be able to install with `-S` unless you
  change the relevant line in the script

However, I do not recommend changing many things it without editing other
components of the script, otherwise you may run into unexpected errors.

### The `progs.csv` list

SHS will parse the given programs list and install all given programs. Note
that the programs file must be a three column `.csv`.

The first column is a "tag" that determines how the program is installed, ""
(blank) for the main repository, `F` to install a flatpak, `A` for instllation
via the AUR, `P` to install via pipx or `G` if the program is a
git repository that is meant to be `make && sudo make install`ed.

The second column is the name of the program in the repository, or the link to
the git repository, and the third column is a description (should be a verb
phrase) that describes the program. During installation, SHS will print out
this information in a grammatical sentence. It also doubles as documentation
for people who read the CSV and want to install my dotfiles manually.

Depending on your own build, you may want to tactically order the programs in
your programs file. SHS will install from the top to the bottom.

If you include commas in your program descriptions, be sure to include double
quotes around the whole description to ensure correct parsing.

### The script itself

The script is extensively divided into functions for easier readability and
trouble-shooting. Most everything should be self-explanatory.

The main work is done by the `installationloop` function, which iterates
through the programs file and determines based on the tag of each program,
which commands to run to install it. You can easily add new methods of
installations and tags as well.

Note that programs from the AUR can only be built by a non-root user. What
SHS does to bypass this by default is to temporarily allow the newly created
user to use `sudo` without a password (so the user won't be prompted for a
password multiple times in installation). This is done ad-hocly, but
effectively with the `newperms` function. At the end of installation,
`newperms` removes those settings, giving the user the ability to run only
several basic sudo commands without a password (`shutdown`, `reboot`,
`pacman -Syu`).


## Extra

Whilst SHS installs all the necessary software and configures the base system, there are
still some extra things to do, as specified below. This includes:

KVM setup: Configuring KVM and VirtManager must be done manually.

DNS Crypt - This is a privacy measure to ensure that DNS traffic is hidden from any unwanted
observers.

Fix QEMU bug - Without doing this, you may notice that CapsLock is automatically pressed after
about a second of pressing it once, this can be super annoying and distruptive for vim based
workflows, but also in general. So we remap it on the Host OS to bypass this bug.

Setting up autologin: This saves time, you don't want to login manually every time you use
your device. Unless your device is unencrypted. Since I have FDE, autologin is a waste of time.

## KVM


### Virt-Manager

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


## DNS Crypt

```
sudo -i
```
```
mkdir -p /opt/dnscrypt-proxy
```
```
cd /opt/dnscrypt-proxy/
```
```
curl -L -O https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.12/dnscrypt-proxy-linux_x86_64-2.1.12.tar.gz
```
```
tar -xvf dnscrypt-proxy-linux_x86_64-2.1.12.tar.gz
```
```
mv linux-x86_64/* .
```
```
rmdir linux-x86_64
```
```
cp example-dnscrypt-proxy.toml dnscrypt-proxy.toml
```
```
./dnscrypt-proxy
```
This will run in the background, so do the next steps in a new terminal.

```
sudo -i
```
```
cd /opt/dnscrypt-proxy/
```
```
mv /etc/resolv.conf /etc/resolv.conf.bak
```
```
nvim /etc/resolv.conf
```
```
nameserver 127.0.0.1
options edns0
```
```
./dnscrypt-proxy -resolve example.com
```
```
./dnscrypt-proxy -service install
```
```
./dnscrypt-proxy -service start
```
```
nvim dnscrypt-proxy.toml
```
```
[anonymized_dns]
routes = [
...
]
```
```
./dnscrypt-proxy -service restart
```

## Spice bug workaround

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

# Whonix Install

Click <a href="https://www.whonix.org/wiki/KVM">here</a> to download Whonix.

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
sh refreshvms
```

## Autologin
```
cd /etc/systemd/system/getty.target.wants
```
```
sudo nvim getty@tty1.service
```
```
ExecStart=-/usr/bin/agetty --autologin user --noreset --noclear --issue-file=/etc/issue:/etc/issue.d:/run/issue.d:/usr/lib/issue.d - ${TERM}
```
```
sudo systemctl restart getty@tty1.service
```
