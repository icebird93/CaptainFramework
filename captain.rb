# Dependencies
require 'io/console'
require 'fileutils'
require 'tempfile'
require 'date'

# Internal dependencies
require_relative 'include/configuration'
require_relative 'include/base'

# Type specific modules
require_relative 'include/local'
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
	def source_setup_step_add(step)
		@config["source"]["setup"][step] = true
	end
	def source_setup_step_remove(step)
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
			@source.setup_environment if @config["source"]["setup"]["environment"]
			@source.setup_capabilities
			@source.setup_test if @config["source"]["setup"]["test"]

			# Finish setup if both source and destination are ready
			_setup_finish if (@destination && @destination.get_ip)
		rescue Exception => exception
			@source = false
			_log(exception.message)
			p exception if $verbose
			puts "[ERROR] SOURCE machine setup failed"
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
			@destination.setup_environment if @config["destination"]["setup"]["environment"]
			@destination.setup_capabilities
			@destination.setup_test if @config["destination"]["setup"]["test"]

			# Finish setup if both source and destination are ready
			_setup_finish if (@source && @source.get_ip)
		rescue Exception => exception
			@destination = false
			_log(exception.message)
			p exception if $verbose
			puts "[ERROR] DESTINATION machine setup failed"
			exit
		end
	end

	# Finish
	def finish
		# Cleanup instances
		@source.setup_cleanup
		@destination.setup_cleanup

		# Destroy instances
		@source.setup_destroy if @config["source"]["finish"]["destroy"]
		@destination.setup_destroy if @config["destination"]["finish"]["destroy"]
	end

	########################
	# Container management #
	########################

	# Execute command in container
	def source_docker_start_command(container, command, options="")
		return @source.docker_start_command(container, command, options)
	end
	def destination_docker_start_command(container, command, options="")
		return @destination.docker_start_command(container, command, options)
	end
	def source_docker_create_command(container, command, options="")
		return @source.docker_create_command(container, command, options)
	end
	def destination_docker_create_command(container, command, options="")
		return @destination.docker_create_command(container, command, options)
	end

	# Launch container
	def source_docker_start_image(container, image, options="")
		return @source.docker_start_image(container, image, options)
	end
	def destination_docker_start_image(container, image, options="")
		return @destination.docker_start_image(container, image, options)
	end
	def source_docker_create_image(container, image, options="")
		return @source.docker_create_image(container, image, options)
	end
	def destination_docker_create_image(container, image, options="")
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
	def migrate_source_to_destination(id_source, id_destination)
		# Check container first
		if !@source.docker_check(id_source)
			puts "[ERROR] Container is not running on source" 
			return false
		end

		# Migrate
		_time = _migrate_source_to_destination_docker(id_source, id_destination)

		# Finish
		if _time && (_time.has_key? "total")
			if ($verbose && _time["copy"]>0)
				puts "[INFO] Checkpoint: #{_time['checkpoint'].round(3)} seconds"
				puts "[INFO] Copy: #{_time['copy'].round(3)} seconds"
				puts "[INFO] Restore: #{_time['restore'].round(3)} seconds"
			end
			puts "[OK] Container migrated (to DESTINATION) in total #{_time['total'].round(3)} seconds"
		else
			puts "[ERROR] Container cannot be migrated (to DESTINATION)"
		end
		return _time
	end
	def migrate_destination_to_source(id_destination, id_source)
		# Check container first
		if !@destination.docker_check(id_destination)
			puts "[ERROR] Container is not running on destination" 
			return false
		end

		# Migrate
		_time = _migrate_destination_to_source_docker(id_destination, id_source)

		# Finish
		if _time && (_time.has_key? "total")
			if ($verbose && _time["copy"]>0)
				puts "[INFO] Checkpoint: #{_time['checkpoint'].round(3)} seconds"
				puts "[INFO] Copy: #{_time['copy'].round(3)} seconds"
				puts "[INFO] Restore: #{_time['restore'].round(3)} seconds"
			end
			puts "[OK] Container migrated (to SOURCE) in total #{_time['total'].round(3)} seconds"
		else
			puts "[ERROR] Container cannot be migrated (to SOURCE)"
		end
		return _time
	end

	#########################
	# Statistics management #
	#########################

	# Measure migration statistics
	def stats_migration(config_stats, config_migration)
		puts "[INFO] Checking stats_migration arguments" if $verbose

		# Check configs
		if (!config_stats || !config_migration)
			puts "[ERROR] Invalid configuration (both configs are required)"
			return false
		end

		# Check migration config
		if (!config_migration["type"] || !(['command','image'].include? config_migration["type"]))
			puts "[ERROR] Invalid migration type, supported: command/image"
			return false
		end

		# Prepare
		_iterations = config_stats["iterations"] || 3
		_logfile = config_stats["log"] || $location+"/logs/stats.csv"
		_sumfile = _logfile.gsub(/(\.csv)$/, '.summary\1')
		_min_to = _min_back = false
		_max_to = _max_back = false
		_avg_to = _avg_back = 0

		# Create and start required containers
		case config_migration["type"]
			when "command"
				source_docker_start_command(config_migration["name"], config_migration["command"], config_migration["options"]||"")
				destination_docker_create_command(config_migration["name"], config_migration["command"], config_migration["options"]||"")
			when "image"
				source_docker_start_image(config_migration["name"], config_migration["image"], config_migration["options"]||"")
				destination_docker_create_image(config_migration["name"], config_migration["image"], config_migration["options"]||"")
		end

		# Reset results file (with header)
		File.truncate(_logfile, 0) if File.exist?(_logfile)
		open(_logfile, 'a'){ |f| f.puts("iteration;datetime;s2d_checkpoint;s2d_copy;s2d_restore;s2d_total;d2s_checkpoint;d2s_copy;d2s_restore;d2s_total") }

		# Do iterations
		_skipped = _skipped_row = 0
		for i in 0.._iterations
			# Prepare iteration
			if $debug
				puts "[INFO] Warmup phase" if i==0
				puts "[INFO] Iteration: #{i}" if i>0
			end

			# Migrate
			_time_to = migrate_source_to_destination(source_docker_id(config_migration["name"]), destination_docker_id(config_migration["name"]))
			_time_back = migrate_destination_to_source(destination_docker_id(config_migration["name"]), source_docker_id(config_migration["name"]))

			# Check results
			if (!_time_to || !_time_back)
				if i>0
					puts "[ERROR] Migration failed, skipping"
					_skipped += 1
				end
				_skipped_row += 1
				if _skipped_row>5
					puts "[ERROR] Aborted migration tests due to consecutive errors"
					return false
				end
				sleep(4)
				next
			end

			# Save stats
			if i>0
				_min_to = _time_to["total"] if (i==1 || _time_to["total"]<_min_to)
				_min_back = _time_back["total"] if (i==1 || _time_back["total"]<_min_back)
				_max_to = _time_to["total"] if (i==1 || _time_to["total"]>_max_to)
				_max_back = _time_back["total"] if (i==1 || _time_back["total"]>_max_back)
				_avg_to += _time_to["total"]
				_avg_back += _time_back["total"]

				# Log results
				open(_logfile, 'a'){ |f| f.puts(i.to_s+";"+DateTime.now.strftime('%Y-%m-%d %H:%M:%S')+";"+_time_to["checkpoint"].round(4).to_s+";"+_time_to["copy"].round(4).to_s+";"+_time_to["restore"].round(4).to_s+";"+_time_to["total"].round(4).to_s+";"+_time_back["checkpoint"].round(4).to_s+";"+_time_back["copy"].round(4).to_s+";"+_time_back["restore"].round(4).to_s+";"+_time_back["total"].round(4).to_s+"\n") }
			end

			# Finish iteration (sleep 1-4 seconds before next migration)
			sleep(1+rand(0..3))
		end

		# Finalize statistics
		_min = [_min_to, _min_back].min
		_max = [_max_to, _max_back].max
		if _iterations-_skipped>0
			_avg = (_avg_to + _avg_back) / (2 * (_iterations-_skipped))
			_avg_to /= (_iterations-_skipped)
			_avg_back /= (_iterations-_skipped)
		end

		# Show results
		puts "[OK] Migrated successfully #{_iterations-_skipped} times"
		if _iterations-_skipped>0
			puts "SOURCE >> DESTINATION: #{_min_to.round(3)} / #{_avg_to.round(3)} / #{_max_to.round(3)}"
			puts "DESTINATION >> SOURCE: #{_min_back.round(3)} / #{_avg_back.round(3)} / #{_max_back.round(3)}"
			puts "Summarized: #{_min.round(3)} / #{_avg.round(3)} / #{_max.round(3)}"

			# Save to file
			File.truncate(_sumfile, 0) if File.exist?(_sumfile)
			open(_sumfile, 'a') do |f|
				f.puts("name;minimum;average;maximum")
				f.puts("SOURCE to DESTINATION;#{_min_to.round(4)};#{_avg_to.round(4)};#{_max_to.round(4)}")
				f.puts("DESTINATION to SOURCE;#{_min_back.round(4)};#{_avg_back.round(4)};#{_max_back.round(4)}")
				f.puts("summarized;#{_min.round(4)};#{_avg.round(4)};#{_max.round(4)}")
			end
		else
			# No valid results
			return false
		end

		# Finish
		return { "to" => { "min" => _min_to.round(4), "avg" => _avg_to.round(4), "max" => _max_to.round(4) }, "back" => { "min" => _min_back.round(4), "avg" => _avg_back.round(4), "max" => _max_back.round(4) }, "summary" => { "min" => _min.round(4), "avg" => _avg.round(4), "max" => _max.round(4) } }
	end

	# Read previous measurement CSV and summarize statistics
	def stats_recalculate(file)
		# Check file
		return false unless File.exist?(file)

		# Reset
		_min_to = _min_back = false
		_max_to = _max_back = false
		_avg_to = _avg_back = 0

		# Read line by line
		iterations = 0
		File.foreach(file).with_index do |line, iteration|
			if iteration>0
				# Read
				_iteration, _stamp, _s2d_checkpoint, _s2d_copy, _s2d_restore, _s2d_total, _d2s_checkpoint, _d2s_copy, _d2s_restore, _d2s_total = line.split(';')
				iterations += 1

				# Fix types
				_s2d_total = _s2d_total.to_f
				_d2s_total = _d2s_total.to_f

				# Collect stats
				_min_to = _s2d_total if (iteration==1 || _s2d_total<_min_to)
				_min_back = _d2s_total if (iteration==1 || _d2s_total<_min_back)
				_max_to = _s2d_total if (iteration==1 || _s2d_total>_max_to)
				_max_back = _d2s_total if (iteration==1 || _d2s_total>_max_back)
				_avg_to += _s2d_total
				_avg_back += _d2s_total
			end
		end

		# Finalize statistics
		_min = [_min_to, _min_back].min
		_max = [_max_to, _max_back].max
		_avg = (_avg_to + _avg_back) / (2 * iterations)
		_avg_to /= iterations
		_avg_back /= iterations

		# Show results
		puts "SOURCE >> DESTINATION: #{_min_to.round(3)} / #{_avg_to.round(3)} / #{_max_to.round(3)}"
		puts "DESTINATION >> SOURCE: #{_min_back.round(3)} / #{_avg_back.round(3)} / #{_max_back.round(3)}"
		puts "Summarized: #{_min.round(3)} / #{_avg.round(3)} / #{_max.round(3)}"

		# Save to file
		open(file.gsub(/(\.csv)$/, '.summary\1'), 'w') do |f|
			f.puts("name;minimum;average;maximum")
			f.puts("SOURCE to DESTINATION;#{_min_to.round(4)};#{_avg_to.round(4)};#{_max_to.round(4)}")
			f.puts("DESTINATION to SOURCE;#{_min_back.round(4)};#{_avg_back.round(4)};#{_max_back.round(4)}")
			f.puts("summarized;#{_min.round(4)};#{_avg.round(4)};#{_max.round(4)}")
		end
		return true
	end

	###################
	# File management #
	###################

	# Send file to target
	def source_send_file(local, target)
		@source.file_send(local, target)
	end
	def destination_send_file(local, target)
		@destination.file_send(local, target)
	end

	# Retrieve file from target
	def source_retrieve_file(target, local)
		@source.file_retrieve(target, local)
	end
	def destination_retrieve_file(target, local)
		@destination.file_retrieve(target, local)
	end

	# Send file between target
	def copy_source_to_destination(file_source, file_destination)
		# Select archiving mode
		_archiving = false
		if @config["archiving"]
			_archiving = "zip" if @config["archiving"]["zip"] && @capabilities["archiving"]["zip"]
			_archiving = "tar" if @config["archiving"]["tar"] && @capabilities["archiving"]["tar"]
		end

		# Copy
		if @capabilities["directssh"]["source"] && @config["directssh"]
			# Send file directly from source to destination
			@source.file_send_remote(@ips["destination"], file_source, file_destination, _archiving)
		else
			# Retrieve file and then send to destination
			begin
				_dir = @source.command_send("[ -d \"#{file_source}\" ] && echo \"folder\"").eql? "folder"
				tmp = Tempfile.new('copy', "/tmp/captain/transfers")
				if _dir
					File.delete(tmp.path)
					@destination.command_send("[ -d \"#{file_destination}\" ] && rm -rf #{file_destination}")
				end
				@source.file_retrieve(file_source + ((_dir) ? "/*" : ""), tmp.path + ((_dir) ? "/" : ""), _archiving)
				@destination.file_send(tmp.path, file_destination, _archiving)
			rescue Exception => exception
				_log(exception.message)
				p exception if $verbose
				puts "[ERROR] File could not be copied: [S] #{file_source} >> [D] #{file_destination}"
			ensure
				FileUtils.rm_rf(tmp.path) if (_dir && File.exist?(tmp.path))
				tmp.unlink
			end
		end
	end
	def copy_destination_to_source(file_destination, file_source)
		# Select archiving mode
		_archiving = false
		if @config["archiving"]
			_archiving = "zip" if @config["archiving"]["zip"] && @capabilities["archiving"]["zip"]
			_archiving = "tar" if @config["archiving"]["tar"] && @capabilities["archiving"]["tar"]
		end

		# Copy
		if @capabilities["directssh"]["destination"] && @config["directssh"]
			# Send file directly from source to destination
			@destination.file_send_remote(@ips["source"], file_destination, file_source, _archiving)
		else
			# Retrieve file and then send to source
			begin
				_dir = @destination.command_send("[ -d \"#{file_destination}\" ] && echo \"folder\"").eql? "folder"
				tmp = Tempfile.new('copy', "/tmp/captain/transfers")
				if _dir
					File.delete(tmp.path)
					@source.command_send("[ -d \"#{file_source}\" ] && rm -rf #{file_source}")
				end
				@destination.file_retrieve(file_destination + ((_dir) ? "/*" : ""), tmp.path + ((_dir) ? "/" : ""), _archiving)
				@source.file_send(tmp.path, file_source, _archiving)
			rescue Exception => exception
				_log(exception.message)
				p exception if $verbose
				puts "[ERROR] File could not be copied: [D] #{file_destination} >> [S] #{file_source}"
			ensure
				FileUtils.rm_rf(tmp.path) if (_dir && File.exist?(tmp.path))
				tmp.unlink
			end
		end
	end

	###################
	# Private methods #
	###################
	private

	# Finish setup
	def _setup_finish
		puts "Finishing setup..."

		# Get instance IPs
		if @config["source"]["type"]=="aws" && @config["destination"]["type"]=="aws"
			@ips = { "source" => @source.get_ip_private, "destination" => @destination.get_ip_private }
		else
			@ips = { "source" => @source.get_ip, "destination" => @destination.get_ip }
		end

		# Check instances
		raise "SOURCE and DESTINATION seems to be the same" if @ips["source"]==@ips["destination"]

		# Finish node setups
		@source.setup_finish
		@destination.setup_finish

		# Check capabilities first
		_check_capabilites

		# Inject key if no direct SSH capability is present
		if @config["ssh"] && @config["ssh"]["key_inject"] && !(@capabilities["directssh"]["source"] && @capabilities["directssh"]["destination"])
			puts "[INFO] Injecting SSH keys in SOURCE and DESTINATION nodes" if $verbose

			# To source
			if !@capabilities["directssh"]["source"] && (File.exist?(File.expand_path(@config["destination"]["ssh"]["key"]+".pub")))
				@source.file_send(@config["destination"]["ssh"]["key"], "/tmp/id_rsa")
				@source.file_send(@config["destination"]["ssh"]["key"]+".pub", "/tmp/id_rsa.pub")
				@source.command_send("mkdir -p ~/.ssh && chmod 0700 ~/.ssh && mv /tmp/id_rsa* ~/.ssh/ && chmod 0600 ~/.ssh/id_rsa && chmod 0644 ~/.ssh/id_rsa.pub && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys && touch ~/.ssh/config && chmod 0600 ~/.ssh/config && echo \"Host #{@ips["destination"]}\n  User #{@config["destination"]["ssh"]["username"]}\n  PreferredAuthentications publickey\n  IdentityFile ~/.ssh/id_rsa\n\" >> ~/.ssh/config")
			end

			# To destinsation
			if !@capabilities["directssh"]["destination"] && (File.exist?(File.expand_path(@config["source"]["ssh"]["key"]+".pub")))
				@destination.file_send(@config["source"]["ssh"]["key"], "/tmp/id_rsa")
				@destination.file_send(@config["source"]["ssh"]["key"]+".pub", "/tmp/id_rsa.pub")
				@destination.command_send("mkdir -p ~/.ssh && chmod 0700 ~/.ssh && mv /tmp/id_rsa* ~/.ssh/ && chmod 0600 ~/.ssh/id_rsa && chmod 0644 ~/.ssh/id_rsa.pub && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 0600 ~/.ssh/authorized_keys && touch ~/.ssh/config && chmod 0600 ~/.ssh/config && echo \"Host #{@ips["source"]}\n  User #{@config["source"]["ssh"]["username"]}\n  PreferredAuthentications publickey\n  IdentityFile ~/.ssh/id_rsa\n\" >> ~/.ssh/config")
			end

			# Recheck capabilities
			puts "[WARN] Key injection failed" if !_capability_directssh && $verbose
		end

		# Setup NFS
		@nfs = false
		if (@config["nfs"] && @config["nfs"]["enabled"] && (@config["source"]["type"]==@config["destination"]["type"] || @config["nfs"]["force"]))
			puts "[INFO] Setting up NFS shares" if $verbose
			if @capabilities["nfs"]["source"]
				# Source to destination
				@nfs = @source.setup_nfs_server(@ips["destination"]) && @destination.setup_nfs_client(@ips["source"])
				puts "[INFO] NFS: source (server) >> destination" if $verbose
			elsif @capabilities["nfs"]["destination"]
				# Destination to source
				@nfs = @destination.setup_nfs_server(@ips["source"]) && @source.setup_nfs_client(@ips["destination"])
				puts "[INFO] NFS: destination (server) >> source" if $verbose
			end
			if @nfs
				# Enable NFS actions
				@source.nfs_enable
				@destination.nfs_enable
				puts "[OK] NFS share is ready"
			end
		end

		# Get base Docker images
		@source.docker_pull_image("busybox")
		@destination.docker_pull_image("busybox")

		puts "[OK] SOURCE and DESTINATION nodes are ready"
	end

	# Initialize filesystem (create necessary folder and files)
	def _init_filesystem
		# Temporary work directory
		FileUtils::mkdir_p "/tmp/captain"
		FileUtils::mkdir_p "/tmp/captain/transfers"
	end

	# Check capabilities between source and destination
	def _check_capabilites
		_capability_migration
		_capability_directssh
		_capability_archiving
		_capability_nfs

		p @capabilities if $debug
	end

	# Check migration capability (it mifht fail with different processors types)
	def _capability_migration
		# Get capabilites
		_capabilities_source = @source.get_capabilities
		_capabilities_destination = @destination.get_capabilities

		# Check vendors, families and types
		if !(_capabilities_source["cpu"]["vendor"].eql? _capabilities_destination["cpu"]["vendor"]) || (_capabilities_source["cpu"]["family"]!=_capabilities_destination["cpu"]["family"]) || (_capabilities_source["cpu"]["model"]!=_capabilities_destination["cpu"]["model"])
			# Different!
			puts "######"
			puts "[WARN] SOURCE and DESTINATION have different types of processors, thus migration might fail"
			puts "######"
			sleep(3)
		end
	end

	# Check direct SSH capability
	def _capability_directssh
		# Prepare
		@capabilities["directssh"] = {}

		# Source -> Destination
		_response = @source.command_send_remote(@ips["destination"], "echo 'ok'")
		@capabilities["directssh"]["source"] = (_response.eql? "ok")

		# Destination -> Source
		_response = @destination.command_send_remote(@ips["source"], "echo 'ok'")
		@capabilities["directssh"]["destination"] = (_response.eql? "ok")

		return (@capabilities["directssh"]["source"] && @capabilities["directssh"]["destination"])
	end

	# Check compression capabilities
	def _capability_archiving
		# Prepare
		@capabilities["archiving"] = {}

		# Get capabilites
		_capabilities_source = @source.get_capabilities
		_capabilities_destination = @destination.get_capabilities

		# TAR
		@capabilities["archiving"]["tar"] = ((_command('which tar | wc -l').eql? "1") && _capabilities_source["linux"]["archiving"]["tar"] && _capabilities_destination["linux"]["archiving"]["tar"])

		# ZIP
		@capabilities["archiving"]["zip"] = ((_command('echo $(($(which zip | wc -l) + $(which unzip | wc -l)))').eql? "2") && _capabilities_source["linux"]["archiving"]["zip"] && _capabilities_destination["linux"]["archiving"]["zip"])

		return (@capabilities["archiving"]["tar"] || @capabilities["archiving"]["zip"])
	end

	# Check NFS capability
	def _capability_nfs
		# Prepare
		@capabilities["nfs"] = {}
		@capabilities["nfs"]["server"] = {}
		@capabilities["nfs"]["client"] = {}

		# Get capabilites
		_capabilities_source = @source.get_capabilities
		_capabilities_destination = @destination.get_capabilities

		# Check server roles
		@capabilities["nfs"]["server"]["source"] = _capabilities_source["nfs"]["server"]
		@capabilities["nfs"]["server"]["destination"] = _capabilities_destination["nfs"]["server"]
		
		# Check client roles
		@capabilities["nfs"]["client"]["source"] = _capabilities_source["nfs"]["client"]
		@capabilities["nfs"]["client"]["destination"] = _capabilities_destination["nfs"]["client"]

		# Check modes
		@capabilities["nfs"]["source"] = (@capabilities["nfs"]["server"]["source"] && @capabilities["nfs"]["client"]["destination"])
		@capabilities["nfs"]["destination"] = (@capabilities["nfs"]["server"]["destination"] && @capabilities["nfs"]["client"]["source"])

		return (@capabilities["nfs"]["source"] || @capabilities["nfs"]["destination"])
	end

	# Migrations
	def _migrate_source_to_destination_docker(id_source, id_destination)
		# Select "unique" checkpoint name
		_checkpoint = Time.now.to_i

		# Prepare time measurement
		_start = {}
		_finish = {}

		# Create checkpoint, transfer files and restore
		_start["total"] = _start["checkpoint"] = Time.now
		@source.docker_checkpoint_create(id_source, _checkpoint)
		_finish["checkpoint"] = Time.now
		if @nfs
			# Use NFS shares
			_start["copy"] = _finish["copy"] = 0
		else
			# Transfer files
			_start["copy"] = Time.now
			copy_source_to_destination("/tmp/captain/checkpoints/export/#{id_source}/checkpoints/#{_checkpoint}", "/tmp/captain/checkpoints/import/#{_checkpoint}")
			_finish["copy"] = Time.now
		end
		_start["restore"] = Time.now
		_response = @destination.docker_checkpoint_restore(id_destination, _checkpoint)
		p _response if $debug && _response.length>0
		_finish["restore"] = _finish["total"] = Time.now

		# Finish
		return false if (_response.include? "error") || (_response.include? "Error")
		return { "checkpoint" => _finish["checkpoint"]-_start["checkpoint"], "copy" => _finish["copy"]-_start["copy"], "restore" => _finish["restore"]-_start["restore"], "total" => _finish["total"]-_start["total"] }
	end
	def _migrate_destination_to_source_docker(id_destination, id_source)
		# Select "unique" checkpoint name
		_checkpoint = Time.now.to_i

		# Prepare time measurement
		_start = {}
		_finish = {}
		_time = {}

		# Create checkpoint, transfer files and restore
		_start["total"] = _start["checkpoint"] = Time.now
		@destination.docker_checkpoint_create(id_destination, _checkpoint)
		_finish["checkpoint"] = Time.now
		if @nfs
			# Use NFS shares
			_start["copy"] = _finish["copy"] = 0
		else
			# Transfer files
			_start["copy"] = Time.now
			copy_destination_to_source("/tmp/captain/checkpoints/export/#{id_destination}/checkpoints/#{_checkpoint}", "/tmp/captain/checkpoints/import/#{_checkpoint}")
			_finish["copy"] = Time.now
		end
		_start["restore"] = Time.now
		_response = @source.docker_checkpoint_restore(id_source, _checkpoint)
		p _response if $debug && _response.length>0
		_finish["restore"] = _finish["total"] = Time.now

		# Finish
		return false if (_response.include? "error") || (_response.include? "Error")
		return { "checkpoint" => _finish["checkpoint"]-_start["checkpoint"], "copy" => _finish["copy"]-_start["copy"], "restore" => _finish["restore"]-_start["restore"], "total" => _finish["total"]-_start["total"] }
	end

	# Run local command
	def _command(command)
		_ssh = `#{command}`
		return _ssh.strip
	end

	# Detailed statistics logging
	def _log_stats(line)
		open($location+"/logs/stats.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M:%S')+"] "+line+"\n") } if (line.is_a?(String) && !line.empty?)
	end

	# Log a custom text
	def _log(line)
		open($location+"/logs/captain.log", 'a') { |f| f.puts("["+DateTime.now.strftime('%Y-%m-%d %H:%M:%S')+"] "+line+"\n") } if (line.is_a?(String) && !line.empty?)
	end

end