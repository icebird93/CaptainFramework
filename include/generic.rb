require 'securerandom'
require 'net/http'
require 'uri'

# Generic class extender
class CaptainGeneric

	# Include base class (Captain)
	include CaptainBase

	# Initializate class
	def initialize(config)
		# Load baseclass' constructor
		super(config)

		# Initialize variables
		_init_generic

		p @config if $debug
		puts "[OK] Initialized"
	end

	# Creates VM if needed
	def setup_create
		raise NotImplementedError, "cannot create generic virtual machines on the go"
	end

	# Checks VM
	def setup_instance
		# Set IP address variable
		@ip = @config["generic"]["ip"] if !@ip

		# Checking instance
		status = _instance_status
		raise "Instance is not running" if !(status.eql? "running") 

		puts "[OK] Instance is ready"
		return @ip
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
		puts "Stopping instances..."
		_log("setup_destroy")

		# Stop running instance
		_instance_stop

		puts "[OK] All instances stopped"
		return true
	end

	###################
	# Private methods #
	###################
	private

	# Initialize variables
	def _init_generic
		# Reset status 
		@setup = {}

		# Check parameters
		raise "No IP address specified" if !@config["generic"]["ip"]
	end

	# Check instance status
	def _instance_status
		return (_connection_status) ? "running" : "stopped"
	end

	# Stop instance
	def _instance_stop
		command_send("shutdown -P now") if _instance_status.eql? "running"
	end

end