# Dependencies
require 'io/console'
require 'date'

# Internal dependencies
require_relative 'include/configuration'
require_relative 'include/base'
require_relative 'include/aws'

# Captain Framework orchestrator
# @description Orchestrates framework's tasks
# @created 2017
# @requirements ruby(v2)
class Captain

	# Include Configurator
	include CaptainConfiguration

	# Initializate, welcome user
	# @parameters {params}
	# @params verbose=false,debug=false
	def initialize(params=false)
		# Set debug options (can be overriden with custom config)
		if params
			$verbose = params[:verbose]
			$debug = params[:debug]
			@confirm = params[:confirm]
		else
			$verbose = false
			$debug = false
			@confirm = false
		end

		# Initialize configuration
		_init_configuration

		# Save current directory
		$location = File.dirname(__FILE__)
		puts "current directory: "+$location if $verbose

		puts "[OK] Captain initizalized"
	end

	# Control setup steps
	def destination_setup_step_add(step)
		@config["destination"]["setup"][step] = true
	end
	def destination_setup_step_remove(step)
		@config["destination"]["setup"][step] = false
	end

	# Setup (virtual) machine
	def destination_setup()
		begin
			# Check configuration
			raise "destination not initialized" if !@config["destination"]

			# Create destination instance
			case @config["destination"]["type"]
				when "aws"
					@destination = CaptainAws.new(@config["destination"])
				else
					raise "Unsupported destination type "+@config["destination"]["type"]
			end

			# Confirmation
			if !@confirm
				# Display selected actions
				puts "Following actions will be performed:"
				puts "- Create" if @config["destination"]["setup"]["create"]
				puts "- Prepare environment" if @config["destination"]["setup"]["environment"]
				puts "- Tests" if @config["destination"]["setup"]["test"]
				puts "- Destroy" if @config["destination"]["setup"]["destroy"]

				# Accept/Deny
				print "Continue? [y/N] "
				response = STDIN.getch
				puts ""
				if !(response == 'y' || response == 'Y')
					puts "[INFO] Aborted by user"
					exit
				end
			end

			@destination.setup_create if @config["destination"]["setup"]["create"]
			@destination.setup_instance
			@destination.setup_environment if @config["destination"]["setup"]["environment"]
			@destination.setup_test if @config["destination"]["setup"]["test"]
			@destination.setup_destroy if @config["destination"]["setup"]["destroy"]
		rescue Exception => exception
			_log(exception.message)
			p exception if $verbose
			puts "[ERROR] Machine setup failed"
			exit
		end
	end

	###################
	# Private methods #
	###################
	private

	# Log a custom text
	def _log(line)
		open($location+"/logs/captain.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M')+"] "+line+"\n") } if line.is_a?(String)
	end

end