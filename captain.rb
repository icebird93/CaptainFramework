# Dependencies
require 'io/console'
require 'fileutils'
require 'tempfile'
require 'date'

# Internal dependencies
require_relative 'include/configuration'
require_relative 'include/base'

# Type specific modules
require_relative 'include/generic'
require_relative 'include/aws'

# Captain Framework orchestrator
# @description Orchestrates framework's tasks
# @created 2017
# @requirements ruby(v2)
class Captain

	# Include Configurator
	include CaptainConfiguration

	#########
	# Setup #
	#########

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

		# Reset capabilities
		@capabilities = {}

		# Reset instances
		@source = false
		@destination = false

		# Save current directory
		$location = File.dirname(__FILE__)
		puts "current directory: "+$location if $verbose

		# Initialize filesystem
		_init_filesystem

		puts "[OK] Captain initizalized"
	end

	# Control source setup steps
	def destination_setup_step_add(step)
		@config["source"]["setup"][step] = true
	end
	def destination_setup_step_remove(step)
		@config["source"]["setup"][step] = false
	end

	# Setup source (virtual) machine
	def source_setup
		begin
			# Check configuration
			raise "Source not defined" if !@config["source"]

			# Confirmation
			if !@confirm
				# Display selected actions
				puts "Following actions will be performed on SOURCE:"
				puts "- Destroy (on finish)" if @config["source"]["finish"]["destroy"]

				# Accept/Deny
				print "Continue? [y/N] "
				response = STDIN.getch
				puts ""
				if !(response == 'y' || response == 'Y')
					puts "[INFO] Aborted by user"
					exit
				end
			else
				puts "[INFO] Preparing SOURCE"
			end

			# Destination
			@source.setup_create if @config["source"]["setup"]["create"]
			@source.setup_instance
			@source.setup_prepare
			@source.setup_capabilities
			@source.setup_environment if @config["source"]["setup"]["environment"]
			@source.setup_test if @config["source"]["setup"]["test"]

			# Check destination
			_capability_directssh if (@destination && @destination.get_ip)
		rescue Exception => exception
			_log(exception.message)
			p exception if $verbose
			puts "[ERROR] Source machine setup failed"
			exit
		end
	end

	# Control destination setup steps
	def destination_setup_step_add(step)
		@config["destination"]["setup"][step] = true
	end
	def destination_setup_step_remove(step)
		@config["destination"]["setup"][step] = false
	end

	# Setup destination (virtual) machine
	def destination_setup
		begin
			# Check configuration
			raise "Destination not defined" if !@config["destination"]

			# Confirmation
			if !@confirm
				# Display selected actions
				puts "Following actions will be performed on DESTINATION:"
				puts "- Create" if @config["destination"]["setup"]["create"]
				puts "- Prepare environment" if @config["destination"]["setup"]["environment"]
				puts "- Tests" if @config["destination"]["setup"]["test"]
				puts "- Destroy (on finish)" if @config["destination"]["finish"]["destroy"]

				# Accept/Deny
				print "Continue? [y/N] "
				response = STDIN.getch
				puts ""
				if !(response == 'y' || response == 'Y')
					puts "[INFO] Aborted by user"
					exit
				end
			else
				puts "[INFO] Preparing DESTINATION"
			end

			# Destination
			@destination.setup_create if @config["destination"]["setup"]["create"]
			@destination.setup_instance
			@destination.setup_prepare
			@destination.setup_capabilities
			@destination.setup_environment if @config["destination"]["setup"]["environment"]
			@destination.setup_test if @config["destination"]["setup"]["test"]

			# Check source
			_capability_directssh if (@source && @source.get_ip)
		rescue Exception => exception
			_log(exception.message)
			p exception if $verbose
			puts "[ERROR] Destination machine setup failed"
			exit
		end
	end

	# Finish
	def finish
		# Cleanup instances
		@source.setup_destroy if @config["source"]["finish"]["destroy"]
		@destination.setup_destroy if @config["destination"]["finish"]["destroy"]
	end

	########################
	# Container management #
	########################

	# Execute command in container
	def source_docker_start_command(container, command, options)
		return @source.docker_start_command(container, command, options)
	end
	def destination_docker_start_command(container, command, options)
		return @destination.docker_start_command(container, command, options)
	end
	def source_docker_create_command(container, command, options)
		return @source.docker_create_command(container, command, options)
	end
	def destination_docker_create_command(container, command, options)
		return @destination.docker_create_command(container, command, options)
	end

	# Launch container
	def source_docker_start_image(container, image, options)
		return @source.docker_start_image(container, image, options)
	end
	def destination_docker_start_image(container, image, options)
		return @destination.docker_start_image(container, image, options)
	end
	def source_docker_create_image(container, image, options)
		return @source.docker_create_image(container, image, options)
	end
	def destination_docker_create_image(container, image, options)
		return @destination.docker_create_image(container, image, options)
	end

	# Container ID
	def source_docker_id(container)
		return @source.docker_id(container)
	end
	def destination_docker_id(container)
		return @destination.docker_id(container)
	end

	#  Migrate container
	def migrate_source_to_destination(source, destination)
		# Check container first
		if !@source.docker_check(source)
			puts "[ERROR] Container is not running on source" 
			return false
		end

		# Select "unique" checkpoint name
		_checkpoint = Time.now.to_i

		# Create checkpoint, transfer files and restore
		@source.docker_checkpoint_create(source, _checkpoint)
		start = Time.now
		copy_source_to_destination("/tmp/captain/checkpoints/export/#{source}/checkpoints/#{_checkpoint}", "/tmp/captain/checkpoints/import/#{_checkpoint}")
		@destination.docker_checkpoint_restore(destination, _checkpoint)
		finish = Time.now

		puts "[INFO] Container migrated in #{finish - start} seconds"
		return true
	end
	def migrate_destination_to_source(destination, source)
		# Check container first
		if !@destination.docker_check(destination)
			puts "[ERROR] Container is not running on destination" 
			return false
		end

		# Select "unique" checkpoint name
		_checkpoint = Time.now.to_i

		# Create checkpoint, transfer files and restore
		@destination.docker_checkpoint_create(destination, _checkpoint)
		start = Time.now
		copy_destination_to_source("/tmp/captain/checkpoints/export/#{destination}/checkpoints/#{_checkpoint}", "/tmp/captain/checkpoints/import/#{_checkpoint}")
		@source.docker_checkpoint_restore(source, _checkpoint)
		finish = Time.now

		puts "[INFO] Container migrated in #{finish - start} seconds"
		return true
	end

	###################
	# File management #
	###################

	# Send file to target
	def source_send_file(local, remote)
		@source.file_send(local, remote)
	end
	def destination_send_file(local, remote)
		@destination.file_send(local, remote)
	end

	# Retrieve file from target
	def source_retrieve_file(remote, local)
		@source.file_retrieve(remote, local)
	end
	def destination_retrieve_file(remote, local)
		@destination.file_retrieve(remote, local)
	end

	# Send file between target
	def copy_source_to_destination(source, destination)
		if @capabilities["directssh"]["source"]
			# Send file directly from source to destination
			@source.file_send_remote(@destination.get_ip, source, destination)
		else
			# Retrieve file and then send to destination
			begin
				tmp = Tempfile.new('copy', "/tmp/captain/transfers")
				source_retrieve_file(source, tmp.path)
				destination_send_file(tmp.path, destination)
			rescue Exception => exception
				_log(exception.message)
				p exception if $verbose
				puts "[ERROR] File could not be copied: [S] #{source} >> [D] #{destination}"
			ensure
				tmp.unlink
			end
		end
	end
	def copy_destination_to_source(destination, source)
		if @capabilities["directssh"]["destination"]
			# Send file directly from source to destination
			@destination.file_send_remote(@source.get_ip, destination, source)
		else
			# Retrieve file and then send to source
			begin
				tmp = Tempfile.new('copy', "/tmp/captain/transfers")
				destination_retrieve_file(destination, tmp.path)
				source_send_file(tmp.path, source)
			rescue Exception => exception
				_log(exception.message)
				p exception if $verbose
				puts "[ERROR] File could not be copied: [D] #{destination} >> [S] #{source}"
			ensure
				tmp.unlink
			end
		end
	end

	###################
	# Private methods #
	###################
	private

	# Initialize filesystem (create necessary folder and files)
	def _init_filesystem
		# Temporary work directory
		FileUtils::mkdir_p "/tmp/captain"
		FileUtils::mkdir_p "/tmp/captain/transfers"
	end

	# Check direct SSH capability between source and destination
	def _capability_directssh
		# Prepare
		@capabilities["directssh"] = {}

		# Source -> Destination
		_response = @source.command_send_remote(@destination.get_ip, "echo 'ok'")
		@capabilities["directssh"]["source"] = (_response.eql? "ok")

		# Destination -> Source
		_response = @destination.command_send_remote(@source.get_ip, "echo 'ok'")
		@capabilities["directssh"]["destination"] = (_response.eql? "ok")

		p @capabilities if $debug
		return (@capabilities["directssh"]["source"] && @capabilities["directssh"]["destination"])
	end

	# Log a custom text
	def _log(line)
		open($location+"/logs/captain.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M')+"] "+line+"\n") } if (line.is_a?(String) && !line.empty?)
	end

end