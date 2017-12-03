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

	# Prepares environment
	def setup_environment
		puts "Preparing environment..."
		puts "[INFO] This might take a few minutes"
		_log("setup_environment")

		# Install Puppet if needed
		_setup_puppet

		# Apply Puppet manifest
		_setup_environment

		puts "[OK] Environment is ready"
		return true
	end

	# Detect machine capabilities
	def setup_capabilities
		puts "Detecting instance capabilities..."

		# Reset capabilities
		@capabilities = {}

		# Setup capabilites
		@capabilities["root"] = _capability_root
		@capabilities["sudo"] = _capability_sudo

		# Check root privileges
		raise "Root permissions (root user and/or sudo) are required to continue" if !@capabilities["root"] && !@capabilities["sudo"]

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
		puts "Configuring NFS server..." if $debug

		# Setup target folder
		command_send("mkdir -p /tmp/captain/nfs && sudo chown nobody:nogroup /tmp/captain/nfs && sudo chmod 0777 /tmp/captain/nfs")

		# Setup share
		command_send("[ \"$(cat /etc/exports | grep '/tmp/captain/nfs' | wc -l)\" -eq 1 ] || (echo '/tmp/captain/nfs #{ip_client}(rw,sync,no_subtree_check,no_root_squash)' | sudo tee --append /etc/exports >/dev/null && sudo systemctl restart nfs-kernel-server && sleep 10 && touch /tmp/captain/nfs/.check)")
		command_send("[ \"$(grep -E '/tmp/captain/nfs.+fsid=' /etc/exports | wc -l)\" -eq 1 ] || sudo sed -i 's|/tmp/captain/nfs #{ip_client}(rw,sync,|/tmp/captain/nfs #{ip_client}(rw,fsid=1,sync,|i' /etc/exports && sudo exportfs -r && sleep 1") if @tmpfs

		# Check exports
		return false unless (command_send("sudo showmount -e localhost | grep /tmp/captain/nfs | wc -l").eql? "1")
		return true
	end
	def setup_nfs_client(ip_server)
		puts "Configuring NFS client..." if $debug
		return true if (command_send("sudo mount | grep '/tmp/captain/nfs' | wc -l").eql? "1")

		# Setup target folder
		command_send("mkdir -p /tmp/captain/nfs && sudo chmod 0777 /tmp/captain/nfs")

		# Connect to server
		command_send("[ \"$(sudo mount | grep '/tmp/captain/nfs' | wc -l)\" -eq 1 ] || (sudo mount #{ip_server}:/tmp/captain/nfs /tmp/captain/nfs && sleep 5 && touch /tmp/captain/nfs/.check)")

		# Check mounts
		_mount = command_send("sudo mount | grep '/tmp/captain/nfs' | wc -l")
		return false if (!_mount || !(_mount.eql? "1"))
		return true
	end
	def destroy_nfs_server
		return true unless (command_send("sudo showmount -e localhost | grep '/tmp/captain/nfs' | wc -l").eql? "1")
		command_send("sed -r -i '/\\/tmp\\/captain\\/nfs [0-9\\.]+\\(rw,/d' /etc/exports && exportfs -r && sleep 1")
		return true
	end
	def destroy_nfs_client
		return true unless (command_send("sudo mount | grep '/tmp/captain/nfs' | wc -l").eql? "1")

		# Detach
		command_send("[ ! \"$(sudo mount | grep '/tmp/captain/nfs' | wc -l)\" -eq 1 ] || (sudo umount /tmp/captain/nfs)")

		# Check mounts
		_mount = command_send("sudo mount | grep '/tmp/captain/nfs' | wc -l")
		return false if (_mount && (_mount.eql? "1"))
		return true
	end

	# Finish setup
	def setup_finish
		# TMPFS
		if (@config["ramdisk"] && @config["ramdisk"]["enabled"])
			# Enable
			@tmpfs = _setup_tmpfs
		else
			# Disable
			@tmpfs = _destroy_tmpfs
		end

		return true
	end

	# Destroy
	def setup_cleanup
	end

	########################
	# Container management #
	########################

	# Execute command in container
	def docker_start_command(container, command, options="")
		# Check if running
		_id = command_send("sudo docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start busybox container with command
		_id = command_send("([ \"$(sudo docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || sudo docker rm -f #{container} &>/dev/null) && sudo docker run -d --name #{container} --security-opt seccomp=unconfined #{options} busybox #{command} | tail -n 1")
		return _id
	end
	def docker_create_command(container, command, options="")
		# Check if running
		_id = command_send("sudo docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Create busybox container with command
		_id = command_send("([ \"$(sudo docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || sudo docker rm -f #{container} &>/dev/null) && sudo docker create --name #{container} --security-opt seccomp=unconfined #{options} busybox #{command} | tail -n 1")
		return _id
	end

	# Launch container
	def docker_start_image(container, image, options="")
		# Check if running
		_id = command_send("sudo docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start image
		_id = command_send("([ \"$(sudo docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || sudo docker rm -f #{container} &>/dev/null) && sudo docker run -d --name #{container} --security-opt seccomp=unconfined #{options} #{image} | tail -n 1")
		return _id
	end
	def docker_create_image(container, image, options="")
		# Check if running
		_id = command_send("sudo docker ps --no-trunc -q -f name=#{container} | tail -n 1")
		return _id if (_id && !(_id.eql? ""))

		# Start image
		_id = command_send("([ \"$(sudo docker ps -a -f name=#{container} | wc -l)\" -eq 1 ] || sudo docker rm -f #{container} &>/dev/null) && sudo docker create --name #{container} --security-opt seccomp=unconfined #{options} #{image} | tail -n 1")
		return _id
	end

	# Create and restore checkpoints
	def docker_checkpoint_create(id, checkpoint)
		return command_send("mkdir -p /tmp/captain/nfs/checkpoints && sudo docker checkpoint create --checkpoint-dir=/tmp/captain/nfs/checkpoints #{id} #{checkpoint} && sudo mv /tmp/captain/nfs/checkpoints/#{id}/checkpoints/#{checkpoint} /tmp/captain/nfs/checkpoints/#{checkpoint} && sudo rm -rf /tmp/captain/nfs/checkpoints/#{id}") if @nfs
		return command_send("sudo docker checkpoint create --checkpoint-dir=/tmp/captain/checkpoints/export #{id} #{checkpoint}")
	end
	def docker_checkpoint_restore(id, checkpoint)
		return command_send("sudo docker start --checkpoint-dir=/tmp/captain/nfs/checkpoints --checkpoint=#{checkpoint} #{id} && sudo rm -rf /tmp/captain/nfs/checkpoints/#{checkpoint}") if @nfs
		return command_send("sudo docker start --checkpoint-dir=/tmp/captain/checkpoints/import --checkpoint=#{checkpoint} #{id} && sudo rm -rf /tmp/captain/checkpoints/import/#{checkpoint}")
	end

	# Get container ID by name
	def docker_id(name)
		return command_send("sudo docker ps -a --no-trunc -f name=#{name} | grep '\\s#{name}$' | tail -n 1 | awk '{ print $1 }'")
	end	

	# Check container
	def docker_check(id)
		return false if command_send("sudo docker ps -f id=#{id} | wc -l").eql? "1"
		return true
	end

	# Get images
	def docker_pull_image(image, tag="latest")
		return command_send("[ \"$(sudo docker images #{image}:#{tag} | wc -l)\" -gt 1 ] || sudo docker pull #{image}:#{tag} &>/dev/null")
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
		# Prepare command
		command = command.gsub('"', '\\"')
		command = command.gsub('$', '\\$')

		# Execute command on target to remote
		return command_send("ssh -oStrictHostKeyChecking=no -oConnectTimeout=8 -t #{ip_remote} \"#{command}\" 2>/dev/null")
	end

	# Sends file to VM using predefined credientals
	def file_send(file_local, file_target, compressed=false)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Local file (#{source}) is not accessible" if (!(file_local[-1].eql? "/") && !(file_local[-2,2].eql? "/*") && !File.exist?(File.expand_path(file_local)))

		# Prepare
		file_local = File.expand_path(file_local.gsub(/\/\*$/, ''))
		file_target = file_target.gsub(/\/$/, '')

		# Send
		if (compressed && !(['.tar.gz','.gz','.zip'].include? File.extname(file_local)))
			# Compress, send, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Sending #{file_local} using TAR archive" if $debug
					`rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname "#{file_local}") && sudo tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename "#{file_local}") && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} /tmp/captain/transfers/#{_tarname}.tar.gz #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz`
					_scp = command_send("tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname \"#{file_target}\") && mv \"$(dirname \"#{file_target}\")/$(basename \"#{file_local}\")\" \"#{file_target}\" && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz")
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Sending #{file_local} using ZIP archive" if $debug
					`rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname "#{file_local}") && sudo zip -rq /tmp/captain/transfers/#{_zipname}.zip $(basename "#{file_local}") && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} /tmp/captain/transfers/#{_zipname}.zip #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && rm -f /tmp/captain/transfers/#{_zipname}.zip`
					_scp = command_send("unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname \"#{file_target}\") && mv \"$(dirname \"#{file_target}\")/$(basename \"#{file_local}\")\" \"#{file_target}\" && rm -f /tmp/captain/transfers/#{_zipname}.zip")
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Send uncompressed
			puts "[INFO] Sending #{file_local}" if $debug
			_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} "#{file_local}" #{@config["ssh"]["username"]}@#{@ip}:"#{file_target}" 2>/dev/null`
		end
		return _scp
	end
	def file_send_remote(ip_remote, file_target, file_remote, compressed=false)
		# Prepare
		file_target = file_target.gsub(/\/\*$/, '')
		file_remote = file_remote.gsub(/\/$/, '')

		# Send from from target to remote
		if (compressed && !(['.tar.gz','.gz','.zip'].include? File.extname(file_target)))
			# Compress, send, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Transferring #{file_target} to #{ip_remote} using TAR archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname \"#{file_target}\") && sudo tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename \"#{file_target}\") && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 /tmp/captain/transfers/#{_tarname}.tar.gz #{ip_remote}:/tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz")
					command_send_remote(ip_remote, "tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname \"#{file_remote}\") && mv \"$(dirname \"#{file_remote}\")/$(basename \"#{file_target}\")\" \"#{file_remote}\" && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz")
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Transferring #{file_target} to #{ip_remote} using ZIP archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname \"#{file_target}\") && sudo zip -rq /tmp/captain/transfers/#{_zipname}.zip $(basename \"#{file_target}\") && scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 /tmp/captain/transfers/#{_zipname}.zip #{ip_remote}:/tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && rm -f /tmp/captain/transfers/#{_zipname}.zip")
					command_send_remote(ip_remote, "unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname \"#{file_remote}\") && mv \"$(dirname \"#{file_remote}\")/$(basename \"#{file_target}\")\" \"#{file_remote}\" && rm -f /tmp/captain/transfers/#{_zipname}.zip")
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Send uncompressed
			puts "[INFO] Transferring #{file_target} to #{ip_remote}" if $debug
			command_send("scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 \"#{file_target}\" #{ip_remote}:\"#{file_remote}\" 2>/dev/null")
		end
	end
	def file_sync_remote(ip_remote, file_target, file_remote)
		# Prepare
		file_target = file_target.gsub(/\/\*$/, '')
		file_remote = file_remote.gsub(/\/$/, '')

		# Send from from target to remote
		puts "[INFO] Syncing #{file_target} to #{ip_remote}" if $debug
		command_send("rsync -a \"#{file_target}\" #{ip_remote}:\"#{file_remote}\" 2>/dev/null")
	end

	# Retrieve file from VM
	def file_retrieve(file_target, file_local, compressed=false)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Remote file (#{file_target}) is not accessible" if (!(file_target[-1].eql? "/") && !(file_target[-2,2].eql? "/*") && !(command_send("ls #{file_target} 2>&1 1>/dev/null | wc -l").eql? "0"))

		# Prepare
		file_target = file_target.gsub(/\/\*$/, '')
		file_local = File.expand_path(file_local.gsub(/\/$/, ''))

		# Retrieve
		if (compressed && !(['.tar.gz','.gz','.zip'].include? File.extname(file_target)))
			# Compress, retrieve, uncompress
			case compressed
				when "tar"
					# TAR
					_tarname = Time.now.to_i
					puts "[INFO] Retrieving #{file_target} using TAR archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_tarname}.tar.gz && cd $(dirname \"#{file_target}\") && sudo tar -czf /tmp/captain/transfers/#{_tarname}.tar.gz $(basename \"#{file_target}\")")
					_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_tarname}.tar.gz /tmp/captain/transfers/#{_tarname}.tar.gz 2>/dev/null && tar -xzf /tmp/captain/transfers/#{_tarname}.tar.gz -C $(dirname "#{file_local}") && mv \"$(dirname \"#{file_local}\")/$(basename \"#{file_target}\")\" \"#{file_local}\" && rm -f /tmp/captain/transfers/#{_tarname}.tar.gz`
				when "zip"
					# ZIP
					_zipname = Time.now.to_i
					puts "[INFO] Retrieving #{file_target} using ZIP archive" if $debug
					command_send("rm -f /tmp/captain/transfers/#{_zipname}.zip && cd $(dirname \"#{file_target}\") && sudo zip -rq /tmp/captain/transfers/#{_zipname}.zip $(basename \"#{file_target}\")")
					_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{@config["ssh"]["username"]}@#{@ip}:/tmp/captain/transfers/#{_zipname}.zip /tmp/captain/transfers/#{_zipname}.zip 2>/dev/null && unzip /tmp/captain/transfers/#{_zipname}.zip -d $(dirname "#{file_local}") && mv \"$(dirname \"#{file_local}\")/$(basename \"#{file_target}\")\" \"#{file_local}\" && /tmp/captain/transfers/#{_zipname}.zip`
				else
					raise "Unsupported archiving type "+compressed
			end
		else
			# Retrieve uncompressed
			puts "[INFO] Retrieving #{file_target}" if $debug
			_scp = `scp -rq -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{@config["ssh"]["username"]}@#{@ip}:"#{file_target}" "#{file_local}" 2>/dev/null`
		end
		return _scp
	end

	####################
	# Abstract methods #
	####################

	# Creates and checks VM
	def setup_create
		raise NotImplementedError, "machine_create is not implemented"
	end

	# Starts VM
	def setup_instance
		raise NotImplementedError, "machine_instance is not implemented"
	end

	# Does tests
	def setup_test
		raise NotImplementedError, "machine_test is not implemented"
	end

	# Destroys VM
	def setup_destroy
		raise NotImplementedError, "machine_destroy is not implemented"
	end

	###################
	# Private methods #
	###################
	private

	# Initialize filesystem (create necessary folder and files)
	def _init_filesystem
		# Temporary work directory
		command_send("mkdir -p /tmp/captain/transfers")
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
		@capabilities["cpu"] = _check_cpu
		@capabilities["nfs"] = {}
		@capabilities["nfs"]["server"] = _check_nfs_server
		@capabilities["nfs"]["client"] = _check_nfs_client
		@capabilities["linux"] = {}
		@capabilities["linux"]["archiving"] = _check_archiving
		@capabilities["linux"]["tmpfs"] = _check_tmpfs
		@capabilities["linux"]["ram"] = _check_ram
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
	def _check_cpu
		_processor = command_send("cat /proc/cpuinfo | grep 'model name' | head -n 1 | awk '{$1=$2=$3=\"\";print}' | xargs")
		_vendor = command_send("cat /proc/cpuinfo | grep 'vendor_id' | head -n 1 | awk '{print $3}'")
		_family = command_send("cat /proc/cpuinfo | grep 'cpu family' | head -n 1 | awk '{print $4}'")
		_model = command_send("cat /proc/cpuinfo | grep -E 'model\\s{2,}' | head -n 1 | awk '{print $3}'")
		puts "Processor: #{_processor}"
		return { "processor" => _processor, "vendor" => _vendor, "family" => _family, "model" => _model }
	end
	def _check_archiving
		_tar = command_send("which tar | wc -l")
		_zip = command_send("echo $(($(which zip | wc -l) + $(which unzip | wc -l)))")
		return { "tar" => (_tar.eql? "1"), "zip" => (_tar.eql? "2") }
	end
	def _check_tmpfs
		_tmpfs = command_send("cat /proc/filesystems | grep -E '\Wtmpfs$' | wc -l")
		return false if ((!_tmpfs) || (_tmpfs.eql? "0"))
		return true
	end
	def _check_ram
		_free = Integer(command_send("free -m | grep Mem: | awk '{print $4}'"))
		_total = Integer(command_send("free -m | grep Mem: | awk '{print $2}'"))
		return { "free" => _free, "total" => _total }
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
		_docker = command_send("sudo docker version -f \"{{.Server.Version}}\"")
		raise "Docker not installed or not running" if (!_docker || (_docker.eql? ""))
		puts "Docker: #{_docker}"
		_experimental = command_send("sudo docker version -f \"{{.Server.Experimental}}\"")
		_storage = command_send("sudo docker info 2>/dev/null | grep 'Storage Driver' | awk '{$1=$2=\"\";print}' | xargs")
		puts "[WARN] Docker is not using AUFS as storage engine, errors may occur" if $verbose && !(_storage.eql? "aufs")
		raise "Docker experimental mode should be enabled" if (!_experimental || !(_experimental.eql? "true"))
		return true
	end
	def _check_criu
		_criu = command_send("sudo criu -V 2>/dev/null | awk '{print $2}'")
		raise "CRIU not installed or not in PATH" if (!_criu || (_criu.eql? ""))
		puts "CRIU: #{_criu}"
		return true
	end

	# Environmental setup
	def _setup_puppet
		return true unless command_send("which puppet | wc -l").eql? "0"

		# Upload Puppet installer and run
		puts "[INFO] Installing Puppet" if $verbose
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/install-puppet.sh", "/tmp/captain/install-puppet.sh")
		_debug = command_send("cd /tmp/captain; sudo chmod u+x install-puppet.sh; sudo ./install-puppet.sh;")
		_log(_debug)
		puts _debug if $debug

		# Wait until it reboots
		puts "[INFO] Waiting to reboot" if $verbose
		_retries = 10
		sleep(10)
		until (_retries == 0) || (_instance_status(@instance).eql? "running" && _connection_status) do
			_retries -= 1
			sleep(10)
		end
		puts "[INFO] Target is back online" if $verbose && _retries>0

		# Rebuild filesystem
		_init_filesystem

		# Finish
		command_send("rm -f /tmp/captain/install-puppet.sh")
		return false if command_send("which puppet | wc -l").eql? "0"
		return true
	end
	def _setup_environment
		# Upload Puppet manifest and apply
		puts "[INFO] Sending Puppet manifests" if $verbose
		command_send("rm -rf /tmp/captain/puppet")
		file_send($location+"/assets/shared/puppet", "/tmp/captain/puppet")
		file_send($location+"/assets/#{@config["os"]}/shared/initialize.pp", "/tmp/captain/puppet/#{@config["os"]}_initialize.pp")
		file_send($location+"/assets/#{@config["os"]}/shared/docker.pp", "/tmp/captain/puppet/#{@config["os"]}_docker.pp")
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/install.pp", "/tmp/captain/puppet/#{@config["os"]}_install.pp")
		file_send($location+"/assets/#{@config["os"]}/#{@config["version"]}/finish.pp", "/tmp/captain/puppet/#{@config["os"]}_finish.pp")
		puts "[INFO] Applying Puppet manifest" if $verbose
		_debug = command_send("FACTER_instance_type=#{@config["type"]} sudo puppet apply /tmp/captain/puppet")
		_log(_debug)
		puts _debug if $debug

		# Wait until it reboots
		puts "[INFO] Waiting for instance" if $verbose
		_retries = 10
		sleep(10)
		until (_retries == 0) || (_instance_status(@instance).eql? "running" && _connection_status) do
			_retries -= 1
			sleep(10)
		end
		puts "[INFO] Target is back online" if $verbose && _retries>0

		# Rebuild filesystem
		_init_filesystem

		# Finish
		command_send("rm -rf /tmp/captain/puppet")
		return true
	end

	# Setup TMPFS working space
	def _setup_tmpfs
		return false if (!@config["ramdisk"] || !@config["ramdisk"]["enabled"])
		return true if (command_send("mount | grep -E '/tmp/captain\s' | awk '{print $1}'").eql? "tmpfs")
		_nfs_server = command_send("sudo showmount -e localhost | grep /tmp/captain/nfs | awk '{print $2}'")
		_nfs_client = command_send("sudo mount | grep -E '/tmp/captain/nfs\s' | awk '{print $1}' | awk -F ':' '{print $1}'")
		_size = [(@config["ramdisk"]["size"] || 512), @capabilities["linux"]["ram"]["free"]].min
		destroy_nfs_server if _nfs_server.length>0
		destroy_nfs_client if _nfs_client.length>0
		command_send("([ ! -d \"/tmp/captain\" ] || mv /tmp/captain /tmp/.captain) && mkdir /tmp/captain && sudo mount -t tmpfs -o size=#{_size}m tmpfs /tmp/captain && ([ ! -d \"/tmp/.captain\" ] || (shopt -s dotglob && mv /tmp/.captain/* /tmp/captain/ && shopt -u dotglob && rm -rf /tmp/.captain))")
		@tmpfs = true
		setup_nfs_server(_nfs_server) if _nfs_server.length>0 && (command_send("ls -la /tmp/captain/nfs/.check 2>/dev/null | wc -l").eql? "1")
		setup_nfs_client(_nfs_client) if _nfs_client.length>0
		return true
	end
	def _destroy_tmpfs
		return true unless (command_send("sudo mount | grep -E '/tmp/captain\s' | awk '{print $1}'").eql? "tmpfs")
		_nfs_server = command_send("sudo showmount -e localhost | grep /tmp/captain/nfs | awk '{print $2}'")
		_nfs_client = command_send("sudo mount | grep -E '/tmp/captain/nfs\s' | awk '{print $1}' | awk -F ':' '{print $1}'")
		command_send("([ ! -d \"/tmp/captain\" ] || (rm -rf /tmp/.captain 2>/dev/null && cp -r /tmp/captain /tmp/.captain))")
		destroy_nfs_server if _nfs_server.length>0
		destroy_nfs_client if _nfs_client.length>0
		command_send("sudo umount -f /tmp/captain && ([ ! -d \"/tmp/.captain\" ] || (rm -rf /tmp/captain && mv /tmp/.captain /tmp/captain))")
		@tmpfs = false
		setup_nfs_server(_nfs_server) if _nfs_server.length>0 && (command_send("ls -la /tmp/captain/nfs/.check 2>/dev/null | wc -l").eql? "1")
		setup_nfs_client(_nfs_client) if _nfs_client.length>0
		return true
	end

	# Log a custom text
	def _log(text)
		open($location+"/logs/class.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M:%S')+"] "+text+"\n") } if (text.is_a?(String) && !text.empty?)
	end

end