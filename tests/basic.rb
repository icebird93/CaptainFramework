#!/usr/bin/ruby

# Load Captain
require_relative '../captain.rb'

# Create new instance
captain = Captain.new({verbose:true, debug:true, confirm:true})

# Load configuration
captain.load_configuration(File.expand_path('..', File.dirname(__FILE__))+'/tests/config.yml')

# Check source
captain.source_setup

# Setup target machine
captain.destination_setup

# Test
#captain.copy_source_to_destination("/root/alma", "/root/alma")
#captain.copy_destination_to_source("/root/korte", "/root/korte")
#captain.destination_retrieve_file("/root/alma", "alma")
#captain.source_docker_start_command("looper3", "/bin/sh -c 'i=0; while true; do echo $i; i=$(expr $i + 1); sleep 1; done'")
#captain.destination_docker_create_command("looper3", "/bin/sh -c 'i=0; while true; do echo $i; i=$(expr $i + 1); sleep 1; done'")
#captain.migrate_source_to_destination(captain.source_docker_id("looper3"), captain.destination_docker_id("looper3"))
#captain.migrate_destination_to_source(captain.destination_docker_id("looper3"), captain.source_docker_id("looper3"))
#captain.source_docker_start_image("memapp", "lm-tcpapp", '-e STRESS="-vm-bytes 1000M –vm-hang 0 -m 1 -c 1"')
#captain.destination_docker_create_image("memapp", "lm-tcpapp", '-e STRESS="-vm-bytes 1000M –vm-hang 0 -m 1 -c 1"')
#captain.migrate_source_to_destination(captain.source_docker_id("memapp"), captain.destination_docker_id("memapp"))
#captain.migrate_destination_to_source(captain.destination_docker_id("memapp"), captain.source_docker_id("memapp"))
captain.stats_migration({"iterations" => 1, "log" => "/tmp/stats.memapp.csv"}, {"type" => "image", "name" => "memapp", "image" => "lm-tcpapp", "options" => '-e STRESS="-vm-bytes 1000M –vm-hang 0 -m 1 -c 1"'})

# Finish
captain.finish