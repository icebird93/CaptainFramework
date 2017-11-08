# Install Docker
class captain::ubuntu_docker($ubuntu_release) {
	# Dependencies
	package { ['apt-transport-https','ca-certificates','software-properties-common']:
		ensure => installed
	} ->

	# Add key
	exec { 'gpg_key':
		command => '/usr/bin/curl -fsSL https://download.docker.com/linux/ubuntu/gpg | /usr/bin/apt-key add -'
	} ->

	# Add repository
	exec { 'apt_repository':
		command => "/usr/bin/add-apt-repository \"deb [arch=amd64] https://download.docker.com/linux/ubuntu ${ubuntu_release} stable\""
	} ->

	# Update
	exec { 'apt_update_docker':
		command => '/usr/bin/apt update && /usr/bin/apt -y upgrade'
	} ->

	# Install
	package { 'docker-ce':
		ensure => installed
	} ->

	# Enable experimental
	exec { 'docker_experimental':
		command => '/bin/bash -c "[ \"$(grep -E \'^ExecStart=.*?--experimental=true\' docker.service | wc -l)\" -eq 1 ] || (sed -i \'s/^ExecStart=.*$/& --experimental=true/i\' /etc/systemd/system/multi-user.target.wants/docker.service && echo '{\"experimental\":true}' > /etc/docker/daemon.json && systemctl daemon-reload && service docker restart)"'
	}
}