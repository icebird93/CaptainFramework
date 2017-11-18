#!/bin/bash
set -e

# Fix slow and buggy sources (change to German sources, modify if needed)
sed -i 's/eu-central-1\.ec2\.archive\.ubuntu\.com/de.archive.ubuntu.com/i' /etc/apt/sources.list

# Prepare
apt update -y
DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --force-yes

# Download and install Puppet for Debian (Jessie)
wget https://apt.puppetlabs.com/puppetlabs-release-pc1-xenial.deb
sudo dpkg -i puppetlabs-release-pc1-xenial.deb
rm -f puppetlabs-release-pc1-xenial.deb
apt update -y
apt install -y puppet

# Enable /etc/rc.local feature
wget https://s3.eu-central-1.amazonaws.com/captain-framework/other/ubuntu/17.10/rc-local.service -O /etc/systemd/system/rc-local.service
touch /etc/rc.local
chmod +x /etc/rc.local
systemctl enable rc-local.service

# Install Puppet modules
puppet module install puppetlabs-reboot

# Finish
{ sleep 1; reboot -f; } >/dev/null &