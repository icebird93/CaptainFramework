# Finish
class captain::finish {
	# Cleanup install files
	exec { 'cleanup install':
		command => 'rm -rf /tmp/captain/install'
	}
}