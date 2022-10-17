# Agent Status Check fact aims to have all chunks reporting as true, indicating ideal state, any individual chunk reporting false should be alerted on and checked against documentation for next steps
# Use shared logic from PEStatusCheck
# Disabled by default requires bundled class too create /opt/puppetlabs/puppet/cache/status_check_enable

Facter.add(:agent_status_check, type: :aggregate) do
  confine { !Facter.value(:pe_build) }
  confine { PEStatusCheck.enabled? }
  require 'puppet'

  chunk(:AS001) do
    # Is the hostcert expiring within 90 days
    #
    next unless File.exist?(Puppet.settings['hostcert'])
    raw_hostcert = File.read(Puppet.settings['hostcert'])
    certificate = OpenSSL::X509::Certificate.new raw_hostcert
    result = certificate.not_after - Time.now

    { AS001: result > 7_776_000 }
  end
  chunk(:AS002) do
    # Has the PXP agent establish a connection with a remote Broker
    #
    valid_families = ['windows', 'Debian', 'RedHat', 'Suse']
    next unless valid_families.include?(Facter.value(:os)['family'])
    if Facter.value(:os)['family'] == 'windows'
      result = Facter::Core::Execution.execute('netstat -np tcp', { timeout: PEStatusCheck.facter_timeout })
      { AS002: result.match?(%r{8142\s*ESTABLISHED}) }
    else
      result = Facter::Core::Execution.execute("ss -onp state established '( dport = :8142 )' ", { timeout: (PEStatusCheck.facter_timeout * 2) })
      { AS002: result.include?('pxp-agent') }
    end
  rescue Facter::Core::Execution::ExecutionFailure => e
    Facter.warn("agent_status_check.AS002 failed to get socket status: #{e.message}")
    Facter.debug(e.backtrace)
    { AS002: false }
  end
  chunk(:AS003) do
    # certname is configured in section other than [main]
    #
    { AS003: !Puppet.settings.set_in_section?(:certname, :agent) && !Puppet.settings.set_in_section?(:certname, :server) && !Puppet.settings.set_in_section?(:certname, :user) }
  end
  chunk(:AS004) do
    # Is the host copy of the crl expiring in the next 90 days
    hostcrl = Puppet.settings[:hostcrl]
    next unless File.exist?(hostcrl)

    x509_cert = OpenSSL::X509::CRL.new(File.read(hostcrl))
    { AS004: (x509_cert.next_update - Time.now) > 7_776_000 }
  end
end
