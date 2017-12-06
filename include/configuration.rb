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
				if @config[machine]["ssh"]
					if ((!@config[machine]["ssh"]["username"]) || (@config[machine]["ssh"]["username"].eql? ""))
						# Select username and password, based on instance OS
						case @config[machine]["os"]
							when "ubuntu"
								@config[machine]["ssh"]["username"] = "ubuntu"
							when "mac"
								raise "No username specified for "+machine+" server"
							else
								raise "Unsupported instance OS"
						end
					end

					# Check key file
					raise "No SSH key specified" if ((!@config[machine]["ssh"]["key"]) || (@config[machine]["ssh"]["key"].eql? ""))
					raise "SSH key file does not exist or is not a valid file" if !(File.exist?(File.expand_path(@config[machine]["ssh"]["key"]))) || !(File.file?(File.expand_path(@config[machine]["ssh"]["key"])))
				end
			end

			# Create source instance
			case @config["source"]["type"]
				when "aws"
					@source = CaptainAws.new(@config["source"])
				when "generic"
					@source = CaptainGeneric.new(@config["source"])
				when "local"
					@source = CaptainLocal.new(@config["source"])
				else
					raise "Unsupported source type "+@config["source"]["type"]
			end

			# Create destination instance
			case @config["destination"]["type"]
				when "aws"
					@destination = CaptainAws.new(@config["destination"])
				when "generic"
					@destination = CaptainGeneric.new(@config["destination"])
				when "local"
					@destination = CaptainLocal.new(@config["source"])
				else
					raise "Unsupported destination type "+@config["destination"]["type"]
			end

			# Prepare setup steps
			if (!@config["source"]["setup"])
				@config["source"]["setup"] = @setup
			end
			if (!@config["destination"]["setup"])
				@config["destination"]["setup"] = @setup
			end

			# Defaults
			@config["directssh"] = true unless @config.has_key? "directssh"

			p @config if $debug
			puts "[OK] Configuration loaded" if $verbose
		rescue Exception => message
			puts message if $verbose
			puts "[ERROR] Configuration could not be loaded"
		end
	end

	# Accessors
	attr_reader :config, :setup

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