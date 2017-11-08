require 'io/console'
require 'fileutils'

# Captain Framework base class
# @description Core functionality
# @created 2017
# @requirements ruby(v2)
module CaptainBase

	###########
	# Generic #
	###########

	# Initializate class
	def initialize(config)
		# Save config
		@config = config
		@nfs = false
	end

	# Config management
	def get_config
		return @config
	end

	# Capability management
	def get_capabilities
		return @capabilities
	end

	# IP management
	def get_ip
		return @ip
	end

	# NFS management
	def nfs_enable
		@nfs = true
	end
	def nfs_disable
		@nfs = false
	end

	#########
	# Setup #
	#########

	# Required preparations
	def setup_prepare
		# Initialize filesystem
		_init_filesystem
	end

	# Detect machine capabilities
	def setup_capabilities
		puts "Detecting instance capabilities..."

		# Reset capabilities
		@capabilities = {}

		# Setup capabilites
		@capabilities["root"] = _capability_root
		@capabilities["sudo"] = _capability_sudo

		# Check environment
		_capability_environment

		# Check requirements
		_check_requirements

		p @capabilities if $debug
		puts "[OK] Ready"
		return true
	end

	# Setup NFS shares
	def setup_nfs_server(ip_client)
		# Setup target folder
		command_send("mkdir -p /tmp/captain/nfs && chown nobody:nogroup /tmp/captain/nfs")

		# Setup share
		command_send("[ \"$(cat /etc/exports | grep '/tmp/captain/nfs' | wc -l)\" -eq 1 ] || (echo '/tmp/captain/nfs #{ip_client}(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports && service nfs-kernel-server restart)")
	end
	def setup_nfs_client(ip_server)
		# Setup target folder
		command_send("mkdir -p /tmp/captain/nfs")

		# Connect to server
		command_send("[ \"$(mount | grep '/tmp/captain/nfs' | wc -l)\" -eq 1 ] || (mount #{ip_server}:/tmp/captain/nfs /tmp/captain/nfs && sleep 5)")

		# Check mounts
		_mount = command_send("mount | grep '/tmp/captain/nfs' | wc -l")
		return true if (_mount || (_mount.eql? "1"))
		return false		
	end

	########################
	# Container management #
	########################

	# Execute command in container
	def docker_start_command(container, command, options="")
		# Check if running
		_id = command_send("docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start busybox container with command
		_id = command_send("([ \"$(docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || docker rm -f #{container} &>/dev/null) && docker run -d --name #{container} --security-opt seccomp=unconfined #{options} busybox #{command} | tail -n 1")
		return _id
	end
	def docker_create_command(container, command, options="")
		# Check if running
		_id = command_send("docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Create busybox container with command
		_id = command_send("([ \"$(docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || docker rm -f #{container} &>/dev/null) && docker create --name #{container} --security-opt seccomp=unconfined #{options} busybox #{command} | tail -n 1")
		return _id
	end

	# Launch container
	def docker_start_image(container, image, options="")
		# Check if running
		_id = command_send("docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start image
		_id = command_send("([ \"$(docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || docker rm -f #{container} &>/dev/null) && docker run -d --name #{container} --security-opt seccomp=unconfined #{options} #{image} | tail -n 1")
		return _id
	end
	def docker_create_image(container, image, options="")
		# Check if running
		_id = command_send("docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start image
		_id = command_send("([ \"$(docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || docker rm -f #{container} &>/dev/null) && docker create --name #{container} --security-opt seccomp=unconfined #{options} #{image} | tail -n 1")
		return _id
	end

	# Create and restore checkpoints
	def docker_checkpoint_create(id, checkpoint)
		return command_send("mkdir -p /tmp/captain/nfs/checkpoints && docker checkpoint create --checkpoint-dir=/tmp/captain/nfs/checkpoints #{id} #{checkpoint} && mv /tmp/captain/nfs/checkpoints/#{id}/checkpoints/#{checkpoint} /tmp/captain/nfs/checkpoints/#{checkpoint} && rm -rf /tmp/captain/nfs/checkpoints/#{id}") if @nfs
		return command_send("docker checkpoint create --checkpoint-dir=/tmp/captain/checkpoints/export #{id} #{checkpoint}")
	end
	def docker_checkpoint_restore(id, checkpoint)
		return command_send("docker start --checkpoint-dir=/tmp/captain/nfs/checkpoints --checkpoint=#{checkpoint} #{id}") if @nfs
		return command_send("docker start --checkpoint-dir=/tmp/captain/checkpoints/import --checkpoint=#{checkpoint} #{id}")
	end

	# Get container ID by name
	def docker_id(container)
		return command_send("docker ps -a --no-trunc -q -f name=#{container} | tail -n 1")
	end	

	# Check container
	def docker_check(id)
		return false if command_send("docker ps -f id=#{id} | wc -l").eql? "1"
		return true
	end

	# Get images
	def docker_pull_image(image, tag="latest")
		return command_send("[ \"$(docker images #{image}:#{tag} | wc -l)\" -gt 1 ] || docker pull #{image}:#{tag} &>/dev/null")
	end

	##################
	# Helper methods #
	##################

	# Sends command to VM instance for execution
	def command_send(command)
		# Check target
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)

		# Prepare command
		command = command.gsub('"', '\\"')
		command = command.gsub('$', '\\$')

		# Execute and return result
		_ssh = `ssh -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} -t #{@config["ssh"]["username"]}@#{@ip} "#{command}" 2>/dev/null`
		return _ssh.strip
	end
	def command_send_remote(ip_remote, command)
		# Execute command on target to remote
		command = command.gsub('"', '\\"')
		return command_send("ssh -oStrictHostKeyChecking=no -oConnectTimeout=8 -t #{ip_remote} \"#{command}\" 2>/dev/null")
	end

	# Sends file to VM using predefined credientals
	def file_send(file_local, file_target, compressed=false)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Local file (#{source}) is not accessible" if (!(file_local[-1].eql? "/") && !(file_local[-2,2].eql? "/*") && !File.exist?(file_local))

		# Send
		if (compressed)
			# Compress, send, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Sending #{file_local} using TAR archive" if $debug
					`rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname #{file_local}) && tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename #{file_local}) && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} /tmp/captain/transfers/#{_tarname}.tar.gz #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz`
					_scp = `tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname #{file_target}) && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz`
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Sending #{file_local} using ZIP archive" if $debug
					`rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname #{file_local}) && zip -rq /tmp/captain/transfers/#{_zipname}.zip $(basename #{file_local}) && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} /tmp/captain/transfers/#{_zipname}.zip #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && rm -f /tmp/captain/transfers/#{_zipname}.zip`
					_scp = command_send("unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname #{file_target}) && rm -f /tmp/captain/transfers/#{_zipname}.zip")
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Send uncompressed
			puts "[INFO] Sending #{file_local}" if $debug
			_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{file_local} #{@config["ssh"]["username"]}@#{@ip}:#{file_target} 2>/dev/null`
		end
		return _scp
	end
	def file_send_remote(ip_remote, file_target, file_remote, compressed=false)
		# Send from from target to remote
		if (compressed)
			# Compress, send, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Transferring #{file_target} to #{ip_remote} using TAR archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname #{file_target}) && tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename #{file_target}) && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 /tmp/captain/transfers/#{_tarname}.tar.gz #{ip_remote}:/tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz")
					command_send_remote(ip_remote, "tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname #{file_remote}) && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz")
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Transferring #{file_target} to #{ip_remote} using ZIP archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname #{file_target}) && zip -rq /tmp/captain/transfers/#{_zipname}.zip $(basename #{file_target}) && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 /tmp/captain/transfers/#{_zipname}.zip #{ip_remote}:/tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && rm -f /tmp/captain/transfers/#{_zipname}.zip")
					command_send_remote(ip_remote, "unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname #{file_remote}) && rm -f /tmp/captain/transfers/#{_zipname}.zip")
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Send uncompressed
			puts "[INFO] Transferring #{file_target} to #{ip_remote}" if $debug
			command_send("scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 #{file_target} #{ip_remote}:#{file_remote} 2>/dev/null")
		end
	end
	def file_sync_remote(ip_remote, file_target, file_remote)
		# Send from from target to remote
		puts "[INFO] Syncing #{file_target} to #{ip_remote}" if $debug
		command_send("rsync -a #{file_target} #{ip_remote}:#{file_remote} 2>/dev/null")
	end

	# Retrieve file from VM
	def file_retrieve(file_target, file_local, compressed=false)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Remote file (#{file_target}) is not accessible" if (!(file_target[-1].eql? "/") && !(file_target[-2,2].eql? "/*") && !(command_send("ls #{file_target} 2>&1 1>/dev/null | wc -l").eql? "0"))

		# Retrieve
		if (compressed)
			# Compress, retrieve, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Retrieving #{file_target} using TAR archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname #{file_target}) && tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename #{file_target})")
					_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_tarname}.tar.gz /tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname #{file_local}) && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz`
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Retrieving #{file_target} using ZIP archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname #{file_target}) && tar -czf /tmp/captain/transfers/#{_zipname}.zip $(basename #{file_target})")
					_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_zipname}.zip /tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname #{file_local}) && /tmp/captain/transfers/#{_zipname}.zip`
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Retrieve uncompressed
			puts "[INFO] Retrieving #{file_target}" if $debug
			_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{@config["ssh"]["username"]}@#{@ip}:#{file_target} #{file_local} 2>/dev/null`
		end
		return _scp
	end

	####################
	# Abstract methods #
	####################

	# Creates and checks VM
	def machine_create
		raise NotImplementedError, "machine_create is not implemented"
	end

	# Starts VM
	def machine_instance
		raise NotImplementedError, "machine_instance is not implemented"
	end

	# Prepares environment
	def machine_environment
		raise NotImplementedError, "machine_environment is not implemented"
	end

	# Does tests
	def machine_test
		raise NotImplementedError, "machine_test is not implemented"
	end

	# Destroys VM
	def machine_destroy
		raise NotImplementedError, "machine_destroy is not implemented"
	end

	###################
	# Private methods #
	###################
	private

	# Initialize filesystem (create necessary folder and files)
	def _init_filesystem
		# Temporary work directory
		command_send("mkdir -p /tmp/captain")
		command_send("mkdir -p /tmp/captain/transfers")
		command_send("mkdir -p /tmp/captain/checkpoints")
		command_send("mkdir -p /tmp/captain/checkpoints/export")
		command_send("mkdir -p /tmp/captain/checkpoints/import")
	end

	# Check connection status
	def _connection_status
		response = command_send("echo \"running\"")
		return (response.eql? "running")
	end

	# Capability testing
	def _capability_root
		return true if @config["ssh"]["username"].eql? "root"
		return false
	end
	def _capability_sudo
		_sudoer = command_send("sudo -n -l -U #{@config["ssh"]["username"]} 2>&1 | egrep -c -i \"not allowed to run sudo|unknown user\"")
		return true if _sudoer.eql? "0"
		return false
	end
	def _capability_environment
		_check_hostname
		_check_kernel
		@capabilities["nfs"] = {}
		@capabilities["nfs"]["server"] = _check_nfs_server
		@capabilities["nfs"]["client"] = _check_nfs_client
		@capabilities["linux"] = {}
		@capabilities["linux"]["archiving"] = _check_archiving
		@capabilities["docker"] = _check_docker
		@capabilities["criu"] = _check_criu
	end

	# Capability requirements
	def _check_requirements
		raise "Docker is not available on this machine" if !@capabilities["docker"]
		raise "CRIU is not available on this machine" if !@capabilities["criu"]
	end

	# Environmental checks
	def _check_hostname
		_hostname = command_send("hostname")
		puts "Host: #{_hostname}"
	end
	def _check_kernel
		_kernel = command_send("uname -r")
		puts "Kernel: #{_kernel}"
	end
	def _check_archiving
		_tar = command_send("which tar | wc -l")
		_zip = command_send("echo $(($(which zip | wc -l) + $(which unzip | wc -l)))")
		return { "tar" => (_tar.eql? "1"), "zip" => (_tar.eql? "2") }
	end
	def _check_nfs_server
		_nfs = command_send("dpkg -l | grep nfs-kernel-server | wc -l")
		return false if ((!_nfs) || (_nfs.eql? "0"))
		return true
	end
	def _check_nfs_client
		_nfs = command_send("dpkg -l | grep nfs-common | wc -l")
		return false if ((!_nfs) || (_nfs.eql? "0"))
		return true
	end
	def _check_docker
		_docker = command_send("docker version -f \"{{.Server.Version}}\"")
		raise "Docker not installed or not running" if (!_docker || (_docker.eql? ""))
		puts "Docker: #{_docker}"
		_experimental = command_send("docker version -f \"{{.Server.Experimental}}\"")
		raise "Docker experimental mode should be enabled" if (!_experimental || !(_experimental.eql? "true"))
		return true
	end
	def _check_criu
		_criu = command_send("criu -V 2>/dev/null | awk \"{print $2}\"")
		raise "CRIU not installed or not in PATH" if (!_criu || (_criu.eql? ""))
		puts "CRIU: #{_criu}"
		return true
	end

	# Environmental setup
	def _setup_puppet
		return true unless command_send("which puppet | wc -l").eql? "0"

		# Upload Puppet installer and run
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/install-puppet.sh", "/tmp/captain/install-puppet.sh")
		_debug = command_send("cd /tmp/captain; sudo chmod u+x install-puppet.sh; sudo ./install-puppet.sh;")
		_log(_debug)
		puts _debug if $debug

		# Wait until it reboots
		_retries = 10
		sleep(10)
		until (_retries == 0) || (_instance_status(@instance).eql? "running") do
			_retries -= 1
			sleep(10)
		end

		# Finish
		command_send("rm -f /tmp/captain/install-puppet.sh")
		return false if command_send("which puppet | wc -l").eql? "0"
		return true
	end
	def _setup_environment
		# Upload Puppet manifest and apply
		file_send($location+"/assets/shared/puppet", "/tmp/captain/puppet")
		file_send($location+"/assets/#{@config["os"]}/shared/initialize.pp", "/tmp/captain/puppet/#{@config["os"]}_initialize.pp")
		file_send($location+"/assets/#{@config["os"]}/shared/docker.pp", "/tmp/captain/puppet/#{@config["os"]}_docker.pp")
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/install.pp", "/tmp/captain/puppet/#{@config["os"]}_install.pp")
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/finish.pp", "/tmp/captain/puppet/#{@config["os"]}_finish.pp")
		_debug = command_send("sudo puppet apply /tmp/captain/puppet")
		_log(_debug)
		puts _debug if $debug

		# Wait until it reboots
		_retries = 10
		sleep(10)
		until (_retries == 0) || (_instance_status(@instance).eql? "running") do
			_retries -= 1
			sleep(10)
		end

		# Finish
		command_send("rm -rf /tmp/captain/puppet")
		return true
	end

	# Log a custom text
	def _log(text)
		open($location+"/logs/class.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M')+"] "+text+"\n") } if (text.is_a?(String) && !text.empty?)
	end

end