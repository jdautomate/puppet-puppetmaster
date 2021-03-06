# Setup standalone Puppetserver without anything else extra
#
# == Parameters:
#
# $manage_packetfilter:: Manage IPv4 and IPv6 rules. Defaults to true.
#
# $puppetserver_allow_ipv4:: Allow connections to puppetserver from this IPv4 address or subnet. Example: '10.0.0.0/8'. Defaults to '127.0.0.1.
#
# $puppetserver_allow_ipv6:: Allow connections to puppetserver from this IPv6 address or subnet. Defaults to '::1'.
#
# $server_reports:: Where to store reports. Defaults to 'store'.
#
# $autosign:: Set up autosign entries. Set to true to enable naive autosigning.
#
# $autosign_entries:: List of autosign entries. Requires that autosign is pointing to the path of autosign.conf.
#
# $timezone:: The timezone the server wants to be located in. Example: 'Europe/Helsinki' or 'Etc/UTC'.
#
# $server_foreman:: Is this a foreman server. Defaults to false.
#
# $show_diff:: Show diff in the foreman user interface. Defaults to false.
#
# $hosts_entries:: A hash of host entries to put in /etc/hosts.
#
# $server_external_nodes:: The path to the ENC executable. Defaults to empty string.
class puppetmaster::puppetserver
(
  String                   $timezone = 'Etc/UTC',
  Boolean                  $manage_packetfilter = true,
  String                   $puppetserver_allow_ipv4 = '127.0.0.1',
  String                   $puppetserver_allow_ipv6 = '::1',
  String                   $server_reports = 'store',
  Variant[Boolean, String] $autosign = '/etc/puppetlabs/puppet/autosign.conf',
  Optional[Array[String]]  $autosign_entries = undef,
  Hash                     $hosts_entries = {},
  Boolean                  $show_diff = false,
  Boolean                  $server_foreman = false,
  String                   $server_external_nodes = '',
)
{
  $primary_names = unique([ $facts['fqdn'], $facts['hostname'], 'puppet', "puppet.${facts['domain']}" ])

  class { '::puppetmaster::common':
    primary_names => $primary_names,
    timezone      => $timezone,
    hosts_entries => $hosts_entries,
  }

  file { '/var/files':
    ensure => 'directory',
    mode   => '0660',
    owner  => 'puppet',
    group  => 'puppet',
  }

  file { '/etc/puppetlabs/puppet/fileserver.conf':
    ensure => 'present'
  }

  ini_setting { 'files_path':
    ensure            => present,
    path              => '/etc/puppetlabs/puppet/fileserver.conf',
    section           => 'files',
    setting           => 'path',
    value             => '/var/files',
    key_val_separator => ' ',
    require           => File['/etc/puppetlabs/puppet/fileserver.conf'],
  }

  ini_setting { 'files_allow':
    ensure            => present,
    path              => '/etc/puppetlabs/puppet/fileserver.conf',
    section           => 'files',
    setting           => 'allow',
    value             => '*',
    key_val_separator => ' ',
    require           => File['/etc/puppetlabs/puppet/fileserver.conf'],
  }

  puppet_authorization::rule { 'files':
    match_request_path => '^/puppet/v3/file_(content|metadata)s?/files/',
    match_request_type => 'regex',
    allow              => '*',
    sort_order         => 400,
    path               => '/etc/puppetlabs/puppetserver/conf.d/auth.conf',
  }

  class { '::puppet':
    server                                 => true,
    show_diff                              => $show_diff,
    server_foreman                         => $server_foreman,
    autosign                               => $autosign,
    autosign_entries                       => $autosign_entries,
    server_reports                         => $server_reports,
    server_external_nodes                  => $server_external_nodes,
    server_environment_class_cache_enabled => true,
    require                                => [ File['/etc/puppetlabs/puppet/fileserver.conf'], Puppet_authorization::Rule['files'] ],
  }

  if $manage_packetfilter {
    include ::packetfilter::endpoint

    $firewall_defaults = {
      dport  => '8140',
      proto  => 'tcp',
      action => 'accept',
      tag    => 'default',
    }

    @firewall { '8140 accept incoming agent ipv4 traffic to puppetserver':
      provider => 'iptables',
      source   => $puppetserver_allow_ipv4,
      *        => $firewall_defaults,
    }

    @firewall { '8140 accept incoming agent ipv6 traffic to puppetserver':
      provider => 'ip6tables',
      source   => $puppetserver_allow_ipv6,
      *        => $firewall_defaults,
    }
  }
}
