require 'yaml'

# Configuration submodule
# @description Used to preconfigure Cheppers classes and add configuration functions
module CaptainConfiguration

	# Load configuration file
	def load_configuration(file)
		raise ArgumentError, "Invalid file argument in load_configuration" unless file

		# Try to load file as YAML
		begin
			puts "Reading configuration..."
			@config = YAML.load_file(file)

			# Prepare SSH config
			for machine in ["source","destination"]
				if (@config[machine]["ssh"]) && ((!@config[machine]["ssh"]["username"]) or (!@config[machine]["ssh"]["password"]))
					# Select username and password, based on instance OS
					case @config[machine]["os"]
						when "ubuntu"
							@config[machine]["ssh"]["username"] = "ubuntu"
						when "mac"
							raise "No username specified for "+machine+" server"
						else
							raise "Unsupported instance OS"
					end

					# Check key file
					raise "SSH key file does not exist or is not a valid file" if (File.exist?(@config[machine]["ssh"]["key"])) || (File.file?(@config[machine]["ssh"]["key"]))
				end
			end

			# Prepare setup steps
			if (!@config["destination"]["setup"])
				@config["destination"]["setup"] = @setup
			end

			p @config if $debug
			puts "[OK] Configuration loaded" if $verbose
		rescue Exception => message
			puts message if $verbose
			puts "[ERROR] Configuration could not be loaded"
		end
	end

	# Enable/Disable component
	def component_set(component, status)
		raise ArgumentError, "Invalid component" unless ["create","environment","test","destroy"].include?(component)
		raise ArgumentError, "Invalid component" unless !!status==status
		@components[component] = status
	end

	# Select target instance
	def instance_select(instance)
		@instance = instance
	end

	# Accessors
	attr_reader :configuration, :components
	attr_accessor :verbose, :debug

	###################
	# Private methods #
	###################
	private

	# Initialize default values (called from constructors)
	def _init_configuration
		# Set defaults
		@setup = { "create" => false, "environment" => false, "test" => true, "destroy" => false }
		@config = false
	end

end