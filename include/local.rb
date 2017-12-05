# Local class extender
class CaptainLocal

	# Include base class (Captain)
	include CaptainBase

	# Initializate class
	def initialize(config)
		# Load baseclass' constructor
		super(config)

		# Initialize variables
		_init_local

		p @config if $debug
		puts "[OK] Initialized"
	end

	# Creates VM if needed
	def setup_create
		raise NotImplementedError, "cannot create local machine"
	end

	# Checks VM
	def setup_instance
		return true
	end

	# Prepares environment
	def setup_environment
		return true
	end

	# Does tests
	def setup_test
		puts "Running tests..."
		_log("setup_test")

		puts "[OK] All done"
		return true
	end

	# Destroys VM
	def setup_destroy
		raise NotImplementedError, "cannot destroy local machine"
	end

	##################
	# Helper methods #
	##################

	# Override send command
	def command_send(command)
		return command_send_local(command)
	end

	###################
	# Private methods #
	###################
	private

	# Initialize variables
	def _init_local
		# Reset status 
		@setup = {}
	end

	# Override capability testing
	def _capability_root
		return true if command_send_local("whoami").eql? "root"
		return false
	end
	def _capability_sudo
		_sudoer = command_send_local("sudo -n -l 2>&1 | egrep -c -i \"not allowed to run sudo|unknown user\"")
		return false if !(_sudoer.eql? "0")
		puts "[INFO] Checking sudo rights, enter user password if asked"
		command_send_local("sudo -v")
		return true
	end
end