#!/usr/bin/ruby

# Load Captain
require_relative '../captain.rb'

# Create new instance
captain = Captain.new({verbose:true, debug:true, confirm:true})

# Load configuration
captain.load_configuration(File.expand_path('..', File.dirname(__FILE__))+'/tests/trap.config.yml')

# Setup source machine
captain.source_setup

# Setup target machine
captain.destination_setup

# Do migration tests
captain.stats_migration({"iterations" => 50, "log" => "/tmp/stats.hybrid.csv"}, {"type" => "command", "name" => "looper", "command" => "/bin/sh -c 'i=0; while true; do echo $i; i=$(expr $i + 1); sleep 1; done'"})

# Finish
captain.finish