# Initialize Ubuntu
class captain::ubuntu_initialize {
	# Update and Upgrade
	exec { 'apt_update':
		command => '/usr/bin/apt update && /usr/bin/apt -y upgrade'
	}

	# Install tools and required dependencies
	package { ['curl','wget','vim','iptables-persistent']:
		ensure => installed,
		require => Exec['apt_update']
	}

	# Install audio (required for CRIU restore)
	package { ['linux-sound-base','alsa-base','alsa-utils']:
		ensure => installed,
		require => Exec['apt_update'],
		notify  => Exec['enable_dummy_sound']
	}
	exec { 'enable_dummy_sound':
		command => '/bin/sed -i \'s/^exit 0$/modprobe snd-dummy enable=1 index=0 id="virtual"\nexit 0/\' /etc/rc.local'
	}	
}