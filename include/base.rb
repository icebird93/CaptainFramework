require 'io/console'

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

	##################
	# Helper methods #
	##################

	# Sends command to VM instance for execution
	def command_send(command)
		raise "Configuration not loaded or no VM is running" if (!@config["ssh"]) or (!@ip)
		ssh = `ssh -oStrictHostKeyChecking=no -i #{@config["ssh"]["key"]} -t #{@config["ssh"]["username"]}@#{@ip} "#{command}" #{$debug ? "" : "2>/dev/null"}`
		return ssh
	end

	# Sends file to VM using predefined credientals
	def file_send(source, destination)
		raise "Configuration not loaded or no VM is running" if (!@config["ssh"]) or (!@ip)
		scp = `scp -oStrictHostKeyChecking=no -i #{@config["ssh"]["key"]} \"#{source}\" #{@config["ssh"]["username"]}@#{@ip}:\"#{destination}\" #{$debug ? "" : "2>/dev/null"}`
		return scp
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

	# Log a custom text
	def _log(text)
		open($location+"/logs/class.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M')+"] "+text+"\n") } if text.is_a?(String)
	end

end