# Setup Puppetserver, PuppetDB and Puppetboard
#
# == Parameters:
#
# $manage_packetfilter:: Manage IPv4 and IPv6 rules. Defaults to true.
#
# $puppetserver_allow_ipv4:: Allow connections to puppetserver from this IPv4 address or subnet. Example: '10.0.0.0/8'. Defaults to '127.0.0.1.
#
# $puppetserver_allow_ipv6:: Allow connections to puppetserver from this IPv6 address or subnet. Defaults to '::1'.
#
# $server_reports:: Where to store reports. Defaults to 'store,puppetdb'.
#
# $autosign:: Set up autosign entries. Set to true to enable naive autosigning.
#
# $autosign_entries:: List of autosign entries. Requires that autosign is pointing to the path of autosign.conf.
#
# $timezone:: The timezone the server wants to be located in. Example: 'Europe/Helsinki' or 'Etc/UTC'.
# 
# $puppetdb_database_password:: Database password for puppetdb
#
class puppetmaster::puppetboard
(
  String                   $puppetdb_database_password,
  String                   $timezone = 'Etc/UTC',
  Boolean                  $manage_packetfilter = true,
  String                   $puppetserver_allow_ipv4 = '127.0.0.1',
  String                   $puppetserver_allow_ipv6 = '::1',
  String                   $server_reports = 'store,puppetdb',
  Variant[Boolean, String] $autosign = '/etc/puppetlabs/puppet/autosign.conf',
  Optional[Array[String]]  $autosign_entries = undef,
)
{

  $puppetboard_puppetdb_host              = $facts['fqdn']
  $puppetboard_puppetdb_port              = 8081
  $puppetboard_puppetdb_dashboard_address = "http://${facts['fqdn']}:8080/pdb/dashboard"
  $puppetboard_puppetdb_address           = "https://${facts['fqdn']}:8081/v2/commands"
  $puppetdb_server                        = $facts['fqdn']
  $puppetboard_manage_git                 = true
  $puppetboard_manage_virtualenv          = true
  $puppetboard_reports_count              = 40
  $puppetboard_puppetdb_key               = "${::settings::ssldir}/private_keys/${::fqdn}.pem"
  $puppetboard_puppetdb_ssl_verify        = "${::settings::ssldir}/certs/ca.pem"
  $puppetboard_puppetdb_cert              = "${::settings::ssldir}/certs/${::fqdn}.pem"
  $puppetboard_groups                     = 'puppet'
  # Copy over Puppet keys to a place where Puppetboard can access them
  $puppet_ssldir                          = '/etc/puppetlabs/puppet/ssl'
  $puppetboard_config_dir                 = '/etc/puppetlabs/puppetboard'
  $puppetboard_ssl_dir                    = "${puppetboard_config_dir}/ssl"
  $puppetdb_cert                          = "${puppetboard_ssl_dir}/${::fqdn}.crt"
  $puppetdb_key                           = "${puppetboard_ssl_dir}/${::fqdn}.key"
  $puppetdb_ca_cert                       = "${puppetboard_ssl_dir}/ca.pem"

  class { '::puppetmaster::puppetdb':
    manage_packetfilter        => $manage_packetfilter,
    puppetserver_allow_ipv4    => $puppetserver_allow_ipv4,
    puppetserver_allow_ipv6    => $puppetserver_allow_ipv6,
    server_reports             => $server_reports,
    autosign                   => $autosign,
    autosign_entries           => $autosign_entries,
    puppetdb_database_password => $puppetdb_database_password,
    timezone                   => $timezone,
    before                     => Class['::puppetboard'],
  }

  file { [ $puppetboard_config_dir, $puppetboard_ssl_dir ]:
    ensure  => directory,
    owner   => 'root',
    group   => 'puppetboard',
    mode    => '0750',
    require => Class['::puppetboard'],
  }

  $keys = { "${puppet_ssldir}/certs/${::fqdn}.pem" => $puppetdb_cert,
  "${puppet_ssldir}/private_keys/${::fqdn}.pem"    => $puppetdb_key,
  "${puppet_ssldir}/certs/ca.pem"                  => $puppetdb_ca_cert, }

  # Allow httpd to read Puppetboard's SSL keys
  if $::osfamily == 'RedHat' {
    $seltype = 'httpd_sys_content_t'
  } else {
    $seltype = undef
  }

  $keys.each |$key| {
    exec { $key[1]:
      command => "cp -f ${key[0]} ${key[1]}",
      unless  => "cmp ${key[0]} ${key[1]}",
      path    => ['/bin', '/usr/bin/' ],
      require => [ Class['::puppetmaster::puppetserver'], File[$puppetboard_ssl_dir] ],
    }

    file { $key[1]:
      group   => 'puppetboard',
      mode    => '0640',
      seltype => $seltype,
      require => Exec[$key[1]],
    }
  }

  class { '::apache':
    purge_configs     => true,
    mpm_module        => 'prefork',
    default_vhost     => true,
    default_ssl_vhost => true,
    default_mods      => false,
  }

  if $facts['osfamily'] == 'RedHat' {
    include ::apache::mod::version

    class { '::apache::mod::wsgi':
      wsgi_socket_prefix => '/var/run/wsgi'
    }

  }
  else {
    class { '::apache::mod::wsgi': }
  }

  class { '::puppetboard':
    groups              => $puppetboard_groups,
    puppetdb_host       => $puppetboard_puppetdb_host,
    puppetdb_port       => $puppetboard_puppetdb_port,
    manage_git          => $puppetboard_manage_git,
    manage_virtualenv   => $puppetboard_manage_virtualenv,
    reports_count       => $puppetboard_reports_count,
    puppetdb_key        => $puppetdb_key,
    puppetdb_ssl_verify => $puppetdb_ca_cert,
    puppetdb_cert       => $puppetdb_cert,
  }

  class { '::puppetboard::apache::conf': }

  if $manage_packetfilter {
    @firewall { '00443 accept tls traffic to puppetserver':
      dport  => '443',
      proto  => 'tcp',
      action => 'accept',
      tag    => 'default',
    }
  }
}
