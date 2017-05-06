#!/usr/bin/ruby

# Load Captain
require_relative '../captain.rb'

# Create new instance
captain = Captain.new({verbose:true, debug:true, confirm:true})

# Load configuration
captain.load_configuration('../config.yml')

# Enable all steps
captain.destination_setup_step_add('create')
captain.destination_setup_step_add('environment')
captain.destination_setup_step_add('test')
captain.destination_setup_step_add('destroy')

# Setup target machine
captain.destination_setup