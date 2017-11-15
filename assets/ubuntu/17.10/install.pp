# Install (Ubuntu-specific)
class captain::ubuntu_install {
	# Install NFS tools
	package { ['nfs-kernel-server', 'nfs-common']:
		ensure => installed
	}

	# Install Docker (artful is not yet supported!)
	class { 'captain::ubuntu_docker':
		ubuntu_release => 'zesty'
	}

	# Install CRIU
	netfile { '/tmp/captain/install/criu.deb':
		remote_location => "https://s3.eu-central-1.amazonaws.com/captain-framework/dependencies/ubuntu/17.10/criu_3.6_$::instance_type-amd64.deb",
		mode => '0755',
		before => Package['criu']
	}
	package { ['libprotobuf-dev', 'libprotobuf-c0-dev', 'protobuf-c-compiler', 'protobuf-compiler', 'python-protobuf', 'pkg-config', 'python-ipaddr', 'iproute2', 'libcap-dev', 'libnl-3-dev', 'libnet-dev', 'asciidoc', 'xmlto', 'libaio-dev', 'autofs']:
		ensure => installed
	}
	package { 'criu':
		provider => dpkg,
		source => '/tmp/captain/install/criu.deb'
	}
}