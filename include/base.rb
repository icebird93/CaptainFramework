require 'io/console'
require 'fileutils'

# Captain Framework base class
# @description Core functionality
# @created 2017
# @requirements ruby(v2)
module CaptainBase

	# Initializate class
	def initialize(config)
		# Save config
		@config = config
	end

	# Config management
	def get_config
		return @config
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

	# Capability management
	def get_capabilities
		return @capabilities
	end

	# IP management
	def get_ip
		return @ip
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
	def command_send_remote(ip, command)
		# Execute command on target to remote
		command = command.gsub('"', '\\"')
		return command_send("ssh -oStrictHostKeyChecking=no -oConnectTimeout=8 -t #{ip} \"#{command}\" 2>/dev/null")
	end

	# Sends file to VM using predefined credientals
	def file_send(source, destination)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Local file does not exist" if File.exist?(source)
		_scp = `scp -r -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} "#{source}" #{@config["ssh"]["username"]}@#{@ip}:"#{destination}" 2>/dev/null`
		return _scp
	end
	def file_send_remote(ip, source, destination)
		# Send from from target to remote
		command_send("scp -r -oStrictHostKeyChecking=no -oConnectTimeout=8 \"#{source}\" #{ip}:\"#{destination}\" 2>/dev/null")
	end

	# Retrieve file from VM
	def file_retrieve(source, destination)
		raise "Target machine is not accessible" if (!@config["ssh"] or !@ip)
		raise "Remote file is not accessible" if !(command_send("ls #{source} 2>&1 1>/dev/null | wc -l").eql? "0")
		_scp = `scp -r -oStrictHostKeyChecking=no -oConnectTimeout=8 -i #{@config["ssh"]["key"]} #{@config["ssh"]["username"]}@#{@ip}:"#{source}" "#{destination}" 2>/dev/null`
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
	def _check_docker
		_docker = command_send("docker version -f \"{{.Server.Version}}\"")
		raise "Docker not installed or not running" if (!_docker || (_docker.eql? ""))
		puts "Docker: #{_docker}"
		return false if ((!_docker) || (_docker.eql? ""))
		return true
	end
	def _check_criu
		_criu = command_send("criu -V 2>/dev/null | awk \"{print $2}\"")
		raise "CRIU not installed or not in PATH" if (!_criu || (_criu.eql? ""))
		puts "CRIU: #{_criu}"
		return false if (!_criu || (_criu.eql? ""))
		return true
	end

	# Log a custom text
	def _log(text)
		open($location+"/logs/class.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M')+"] "+text+"\n") } if (text.is_a?(String) && !text.empty?)
	end

end