# Initialize Ubuntu
class captain::ubuntu_initialize {
	# Update and Upgrade
	exec { 'apt_update':
		command => '/usr/bin/apt update && /usr/bin/apt -y upgrade'
	}

	# Install tools
	package { ['curl','wget','vim']:
		ensure => installed,
		require => Exec['apt_update']
	}
}