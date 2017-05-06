#!/bin/bash

# Prepare
apt-get update -y
apt-get upgrade -y

# Download and install Puppet for Debian (Jessie)
wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
sudo dpkg -i puppetlabs-release-trusty.deb
sudo apt-get update
apt-get update -y
apt-get -y install puppet
rm puppetlabs-release-trusty.deb

# Templatedir patch
sed -e '/templatedir/ s/^#*/#/' -i.back /etc/puppet/puppet.conf

# Finish
{ sleep 1; reboot -f; } >/dev/null &