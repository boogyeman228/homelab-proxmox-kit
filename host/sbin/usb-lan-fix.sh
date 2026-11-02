#!/bin/sh
# Watchdog: keep a USB LAN adapter attached to the vmbr0 bridge.
# USB NICs sometimes vanish after boot or a power glitch; this resets the USB
# controller (up to 3 tries) and re-attaches the NIC to the bridge.
# Settings: /etc/default/usb-lan-fix  (IF=<nic name>, PCI=<USB controller PCI address>)
[ -r /etc/default/usb-lan-fix ] && . /etc/default/usb-lan-fix
IF=${IF:?set IF in /etc/default/usb-lan-fix}
PCI=${PCI:?set PCI in /etc/default/usb-lan-fix}
miss=0
while true; do
  sleep 15
  if [ -e /sys/class/net/$IF ]; then
    miss=0
    ip link show $IF | grep -q 'master vmbr0' || { echo "usb-lan-fix: attaching $IF" > /dev/kmsg; ifreload -a; }
  else
    miss=$((miss+1))
    if [ $miss -le 3 ]; then
      echo "usb-lan-fix: $IF missing, resetting USB (try $miss)" > /dev/kmsg
      echo $PCI > /sys/bus/pci/drivers/xhci_hcd/unbind; sleep 2
      echo $PCI > /sys/bus/pci/drivers/xhci_hcd/bind
    fi
  fi
done
