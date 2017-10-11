#!/usr/bin/ruby

# Load Captain
require_relative '../captain.rb'

# Create new instance
captain = Captain.new({verbose:true, debug:true, confirm:true})

# Load configuration
captain.load_configuration(File.expand_path('..', File.dirname(__FILE__))+'/config.yml')

# Setup target machine
captain.source_setup

# Enable all steps
captain.destination_setup_step_add('create')
captain.destination_setup_step_add('environment')
captain.destination_setup_step_add('test')
captain.destination_setup_step_add('destroy')

# Setup target machine
captain.destination_setup

# Finish
captain.finish