# Finish
class captain::finish {
	# Cleanup install files
	exec { 'cleanup install':
		command => '/bin/rm -rf /tmp/captain/install'
	}
}