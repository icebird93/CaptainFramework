#!/usr/bin/ruby

# Load Captain
require_relative '../captain.rb'

# Create new instance
captain = Captain.new({verbose:true, debug:true, confirm:true})

# Load configuration
captain.load_configuration(File.expand_path('..', File.dirname(__FILE__))+'/config.yml')

# Check source
captain.source_setup

# Setup target machine
captain.destination_setup

# Test
#captain.copy_source_to_destination("/root/alma", "/root/alma")
captain.copy_destination_to_source("/root/alma", "/root/alma")
#captain.destination_retrieve_file("/root/alma", "alma")

# Finish
captain.finish