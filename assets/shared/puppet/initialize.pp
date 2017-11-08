# Initialize system
class captain::initialize {
	# Folders
	file { ['/tmp/captain/install']:
		ensure => directory
	}
}