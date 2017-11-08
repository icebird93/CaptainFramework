# Install class
class captain::install {
	# Generic
	class { 'captain::initialize':
		stage => first
	}
	class { 'captain::finish':
		stage => last
	}

	# OS specific
	case $::operatingsystem {
		'ubuntu': {
			class { 'captain::ubuntu_initialize':
				stage => first
			}
			class { 'captain::ubuntu_install': }
			class { 'captain::ubuntu_finish':
				stage => last
			}
		}
	}
}

# All servers
node default {
	class { 'captain::install': }
}