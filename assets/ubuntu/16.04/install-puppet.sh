#!/bin/bash
set -e

# Prepare
apt-get update -y
apt-get upgrade -y

# Download and install Puppet for Debian (Jessie)
wget https://apt.puppetlabs.com/puppetlabs-release-pc1-xenial.deb
sudo dpkg -i puppetlabs-release-pc1-xenial.deb
rm -f puppetlabs-release-pc1-xenial.deb
apt-get update -y
apt-get install -y puppet

# Finish
{ sleep 1; reboot -f; } >/dev/null &