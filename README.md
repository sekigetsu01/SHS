# Sekigetsu's Host Setup

## Installation:

On an Arch-based distribution as root, run the following:

```
git clone https://github.com/sekigetsu01/SHS.git
cd SHS/static
sh shs.sh
```

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
sudo sh refreshvms
```

## Encryption Key Libvirt Issue when reusing SHS

```
sudo mv -v /var/lib/libvirt/secrets/secrets-encryption-key /var/lib/libvirt/secrets/secrets-encryption-key.bk
```

```
sudo systemctl restart libvirtd
```


## Autologin

copy ~/.config/ly/config.ini to /etc/ly/config.ini

```
sudo systemctl enable ly@tty1.service
```
```
sudo systemctl restart ly@tty1.service
```
