# Finish Ubuntu provisioning
class captain::ubuntu_finish {
	Class['captain::finish']->Class['captain::ubuntu_finish']

	reboot { 'after':
		subscribe => Package['linux-image-4.13.5']
	}
}