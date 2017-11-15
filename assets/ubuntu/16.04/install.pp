# Install (Ubuntu-specific)
class captain::ubuntu_install {
	# Install kernel
	netfile { '/tmp/captain/install/linux-image-4.13.5.deb':
		remote_location => 'https://s3.eu-central-1.amazonaws.com/captain-framework/kernel/ubuntu/16.04/linux-image-4.13.5-custom_4.13.5-custom-10.00.Custom_amd64.deb',
		mode => '0755',
		before => Package['linux-image-4.13.5'],
	}
	netfile { '/tmp/captain/install/linux-headers-4.13.5.deb':
		remote_location => 'https://s3.eu-central-1.amazonaws.com/captain-framework/kernel/ubuntu/16.04/linux-headers-4.13.5-custom_4.13.5-custom-10.00.Custom_amd64.deb',
		mode => '0755',
		before => Package['linux-headers-4.13.5'],
	}
	package { 'linux-headers-4.13.5':
		provider => dpkg,
		source => '/tmp/captain/install/linux-headers-4.13.5.deb'
	} ->
	package { 'linux-image-4.13.5':
		provider => dpkg,
		source => '/tmp/captain/install/linux-image-4.13.5.deb'
	} ->
	exec { 'enable_aufs':
		command => '/bin/echo "aufs" >> /etc/modules'
	}

	# Install NFS tools
	package { ['nfs-kernel-server', 'nfs-common']:
		ensure => installed
	}

	# Install Docker
	class { 'captain::ubuntu_docker':
		ubuntu_release => 'xenial'
	}

	# Install CRIU
	netfile { '/tmp/captain/install/criu.deb':
		remote_location => "https://s3.eu-central-1.amazonaws.com/captain-framework/dependencies/ubuntu/16.04/criu_3.6_$::instance_type-amd64.deb",
		mode => '0755',
		before => Package['criu'],
	}
	package { ['libprotobuf-dev', 'libprotobuf-c0-dev', 'protobuf-c-compiler', 'protobuf-compiler', 'python-protobuf', 'pkg-config', 'python-ipaddr', 'iproute2', 'libcap-dev', 'libnl-3-dev', 'libnet-dev', 'asciidoc', 'xmlto', 'libaio-dev', 'autofs']:
		ensure => installed
	}
	package { 'criu':
		provider => dpkg,
		source => '/tmp/captain/install/criu.deb'
	}
}