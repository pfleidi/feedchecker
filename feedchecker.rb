#!/usr/bin/env ruby

# == Synopsis
#
#   This is a simple, multi-threaded script which takes an opml file and
#   checks all contained feeds for errors, redirects and so on.
#   It is also able to partially detect orphaned feeds.
#
# == Examples
#
#   feedchecker.rb -i feeds.opml
#
#   Other examples:
#     feedchecker.rb -t 60 -i input.opml
#     feedchecker.rb -a 365 -t 60 -i input.opml
#
# == Usage
#   feedchecker.rb [options] -i input.opml
#
#   For help use: feedchecker.rb -h
#
# == Options
#   -h, --help          Displays help message
#   -e, --version       Display the version
#   -i, --input         Secify an input file
#   -t, --timeout       Specify a timeout interval in seconds
#   -a, --age           Specify the minimum age in days
#
# == Author
#   Sven Pfleiderer
#
# == Copyright
#   Copyright (c) 2009 Sven Pfleiderer. Licensed under GPL Version 2:
#   http://www.gnu.org/licenses/gpl-2.0.html

require 'net/http'
require 'uri'
require 'rexml/document'
require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'date'
require 'trollop'

class Feedchecker

   def initialize(options)
      @options = options
   end

   def check_feeds
      threads = Array.new
      read_opml.each do |feed|
         threads << Thread.new(feed) do |myFeed|
            resp = get_response(myFeed)
            puts resp if !resp.nil?
         end
      end
      threads.each { |aThread|  aThread.join }
      
   end

   private

   def get_response(url)
      check = String.new

      begin
         ht = URI.parse(url)
         timeout(@options[:timeout]) do
            response = Net::HTTP.get_response(ht)
            check = case response
            when Net::HTTPRedirection   then    " Redirect ... new URI: #{response['location']}"
            when Net::HTTPForbidden     then    " Forbidden ... check URI"
            when Net::HTTPNotFound      then    " Not found ... check URI"
            end
         end
      rescue TimeoutError
         check = " Connection timed out"
      rescue SocketError => socket_error
         check = " #{ht.host} not found"
      rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED
         check =  " Connection to #{ht.host} failed!"
      rescue Net::HTTPBadResponse
         check = " #{ht.host} sends bad HTTP data"
      end
      check = check_age(url) unless check
      url + check if check
   end

   def check_age(url)
      date_now = Time.now
      content = String.new
      begin
         open(url) do |s| content = s.read end
         rss = RSS::Parser.parse(content, false)
         if rss
            feedage = ((date_now - rss.items.first.date).to_i)/(60 * 60 * 24)
            return " is out of date. Age: #{feedage} days without an update" if feedage > @options[:age]
         end
      rescue  NameError, TypeError, OpenURI::HTTPError
         return " age could not be checked"
      rescue RSS::NotWellFormedError
         return " feed isn't well formed and could't be parsed"
      end
   end

   def parse_opml(opml_node)
      feeds = Array.new
      opml_node.elements.each('outline') do |el|
         el.elements.each('outline') do |fe|
            if (fe.attributes['xmlUrl'])
               feeds.push(fe.attributes['xmlUrl'])
            end
         end
      end

      feeds
   end

   def read_opml
      begin
         content = File.read(@options[:input])
         opml = REXML::Document.new(content)
         feeds = parse_opml(opml.elements['opml/body'])
      rescue NoMethodError
         puts "File #{@options[:input]} could not be parsed!"
      rescue
         puts "File #{@options[:input]} not found!"
      end
      return feeds if feeds
   end

end

options = Trollop::options do
   version "feedchecker.rb 0.3 (c) 2009 Sven Pfleiderer"
   banner <<-EOS
This is a simple, script which takes an opml file and checks all contained feeds for errors.

 Usage:

feedchecker.rb [options] -i <filename>

where [options] are:
   EOS
   opt :input,    "Input opml file", :type => String
   opt :timeout,  "Timeout interval in seconds", :default => 60
   opt :age,      "Specify the minimum age in days", :default => 365
end

if (!(File.exist?(options[:input]) if options[:input]) || options[:input].nil?)
   Trollop::die "must specify an existant input file" unless File.exist?(options[:input]) if options[:input]
end

checker = Feedchecker.new(options)
checker.check_feeds