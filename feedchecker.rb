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
#
# ./feedchecker.rb --help
# This is a simple, script which takes an opml file and checks all contained feeds for
# errors.
#
# Usage:
#
# feedchecker.rb [options] -i <filename>
#
# where [options] are:
#          --input, -i <s>:   Input opml file
#        --timeout, -t <i>:   Timeout interval in seconds (default: 60)
#            --age, -a <i>:   Specify the minimum age in days (default: 365)
#  --fetchparallel, -f <i>:   Specify the amount of feeds to fetch parallel (default: 5)
#            --version, -v:   Print version and exit
#               --help, -h:   Show this message
#
# == Author
#   Sven Pfleiderer
#
# == Copyright
#   Copyright (c) 2009 Sven Pfleiderer. Licensed under GPL Version 2:
#   http://www.gnu.org/licenses/gpl-2.0.html

require 'rubygems'
require 'net/http'
require 'net/https'
require 'uri'
require 'rexml/document'
require 'rss/1.0'
require 'rss/2.0'
require 'open-uri'
require 'date'
require 'trollop'
require 'peach'

class Feedchecker

   def initialize(options)
      @options = options
   end

   def check_feeds
      responses = read_opml.pmap(@options[:fetchparallel]) do |feed|
         get_response(feed)
      end

      output = responses.find_all { |item| !item.nil? }
      output.sort.each { |out| puts out}
   end

   private

   def get_response(url)
      check = String.new

      begin
         ht = URI.parse(url)
         timeout(@options[:timeout]) do

            Net::HTTP.start(ht.host, ht.port) do |http|
               response = http.head(ht.request_uri)
               check = case response
               when Net::HTTPRedirection   then    " Redirect ... new URI: #{response['location']}"
               when Net::HTTPForbidden     then    " Forbidden ... check URI"
               when Net::HTTPNotFound      then    " Not found ... check URI"
               end
            end
            
         end
      rescue TimeoutError, Errno::ETIMEDOUT
         check = " Connection timed out"
      rescue SocketError
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

   def parse_opml(document)
      feeds = Array.new
      REXML::XPath.each(document, "//outline[@htmlUrl]") do |fe|
         feeds << fe.attributes['xmlUrl']
      end
      feeds
   end

   def read_opml
      begin
         opml_file = File.read(@options[:input])
         opml_document = REXML::Document.new(opml_file)
         feeds = parse_opml(opml_document)
      rescue NoMethodError
         puts "File #{@options[:input]} could not be parsed!"
      rescue
         puts "File #{@options[:input]} not found!"
      end
      return feeds if feeds
   end

end

options = Trollop::options do
   version "feedchecker.rb 0.4 (c) 2009 Sven Pfleiderer"
   banner <<-EOS
This is a simple, script which takes an opml file and checks all contained feeds for errors.

 Usage:

feedchecker.rb [options] -i <filename>

where [options] are:
   EOS
   opt :input,    "Input opml file", :type => String
   opt :timeout,  "Timeout interval in seconds", :default => 60
   opt :age,      "Specify the minimum age in days", :default => 365
   opt :fetchparallel,   "Specify the amount of feeds to fetch parallel", :default => 5
end

if (options[:input].nil? or !File.exist?(options[:input]))
   Trollop::die "must specify an existant input file"
end

checker = Feedchecker.new(options)
checker.check_feeds
