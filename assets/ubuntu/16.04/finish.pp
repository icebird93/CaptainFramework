# Finish Ubuntu provisioning
class captain::ubuntu_finish {
	Class['captain::finish']->Class['captain::ubuntu_finish']
}