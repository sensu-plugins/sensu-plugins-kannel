#! /usr/bin/env ruby
#
#  metrics-kannel
#
# DESCRIPTION:
#   This plugin checks get metrics for kannel
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   metrics-kannel -h host -P port -p password
#
# NOTES:
#
# LICENSE:
#   Marc-Andre Gatien    <https://github.com/mag009>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/metric/cli'
require 'net/http'
require 'rexml/document'

class Graphite < Sensu::Plugin::Metric::CLI::Graphite
  option :host,
         short: '-h HOST',
         long: '--host HOST',
         description: 'Your Kannel endpoint',
         default: 'localhost'

  option :port,
         short: '-P PORT',
         long: '--port PORT',
         description: 'Your Kannel port',
         default: 13000, # rubocop:disable NumericLiterals
         proc: proc(&:to_i)

  option :password,
         short: '-p PASSWORD',
         long: '--password PASSWORD',
         description: 'Your Kannel password'

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostbyname(Socket.gethostname.to_s).first}.kannel"

  def run
    path = "/status.xml?password=#{config[:password]}"

    begin
      response = Net::HTTP.get(config[:host], path, config[:port])
    rescue => e
      critical e
    end

    document = REXML::Document.new(response)
    critical 'Invalid XML document' if document.root.nil?
    critical 'Invalid root element' if 'gateway' != document.root.name
    critical 'Denied' if 'Denied' == document.root.text.strip
    list = ['received/total', 'sent/total', 'inbound', 'outbound', 'storesize']

    sms = {}
    list.each do |k|
      sms[k.sub('/', '.').to_s] = [REXML::XPath.first(document, "//sms/#{k}/text()")]
    end

    sms.each do |k, v|
      if k =~ /bound/
        v = v.join(',').split(',')
      end
      v = v.first
      output [config[:scheme], k].join('.'), v
    end

    Hash[REXML::XPath.each(document, '//smsc').map do |smsc|
      output [config[:scheme], smsc.text('id'), 'failed'].join('.'), smsc.text('failed')
      output [config[:scheme], smsc.text('id'), 'queued'].join('.'), smsc.text('queued')
      output [config[:scheme], smsc.text('id'), 'received'].join('.'), smsc.text('sms/received')
      output [config[:scheme], smsc.text('id'), 'sent'].join('.'), smsc.text('sms/sent')
      output [config[:scheme], smsc.text('id'), 'inbound'].join('.'), smsc.text('sms/inbound').split(',').first
      output [config[:scheme], smsc.text('id'), 'outbound'].join('.'), smsc.text('sms/outbound').split(',').first
    end]
    ok
  end
end
