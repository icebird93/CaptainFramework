# Update
exec { 'apt-update':
  command => '/usr/bin/apt-get update'
}

# Install curl 
package { 'curl':
  require => Exec['apt-update'],
  ensure => installed
}