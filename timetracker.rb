#!/usr/bin/env ruby

# Copyright 2011 Stephen Duncan Jr
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'time'
require 'enumerator'

now = Time.now
date = now.strftime('%Y-%m-%d')
time = now.strftime('%X')

options = {:count => 5, :save => true}

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage:\n\ttimetracker [options] [file]"
  opts.separator ''
  opts.separator 'Options:'

  opts.on('-p', '--print [DATE]', 'print the row for the current day') do |d|
    options[:print] = d || date
    options[:save] = false
  end
  
  opts.on('-m', '--message MESSAGE', 'add a message to the current day') do |message|
    options[:message] = message.empty? ? '' : message.gsub(/\s+/, ' ').chomp
  end
  
  opts.on('-d', '--dry-run', 'print what the line would have looked like, but do not modify the file') do 
    options[:save] = false
  end
  
  opts.on('-q', '--quitting-time [HOURS]', 'print the time you would have to stop working to meet 8 hours (or the number of provided hours)') do |hours|
    options[:quitting] = (hours || '8').to_f
    options[:save] = false
  end
  
  opts.on('-r', '--repair', 'reparse all lines in the file to ensure the hours worked is correct') {options[:repair] = true}
  
  opts.on('-l', '--list', 'list the most recent entries (limited by -c)') do
    options[:list] = true
    options[:save] = false
  end
  opts.on('-u', '--undo', 'undo the more recent entry') {options[:undo] = true}

  opts.on('-c', '--count [COUNT]', 'restrict list-based functionality to the most recent [COUNT]') do |count|
    options[:count] = count.nil? ? 5 : count.to_i
  end

  opts.on_tail('-h', '-?', '--help', 'brief help message') do
	puts opts
	exit
  end
end

begin
  opt_parser.parse!
rescue
  puts $!, "", opt_parser
  exit
end

filename = ARGV[0] || abort("A timesheet storage file must be provided")

class EntryRow
  attr_accessor :message

  def initialize(date, time, entries=[], message='')
    @date = date
    @time = time
    @entries = entries
    @message = message
    self.repair
  end

  def to_s
    self.to_line
  end

  def to_line
    row = [] << @date << @time
    row.concat(@entries) unless @entries.empty?
    row << @message unless @message.empty?
    row.join(' ' * 4)
  end

  def repair
    @time = sprintf('%4.1f', self.total_time / (60.0 * 60.0))
  end

  def total_time
    @entries.to_enum(:each_slice, 2).inject(0) do |sum, pair|
      (pair.length < 2) ? sum : sum + (Time.parse(pair[1]) - Time.parse(pair[0]))
    end
  end

  def has_started_day?
    not @entries.empty?
  end

  def is_currently_working?
    @entries.length % 2 == 1
  end

  def add_entry(entry)
    @entries << entry
    self.repair
  end

  def pop_entry
    @entries.delete_at(-1)
    self.repair
  end

  def quitting_time(hours)
    (Time.parse(@entries[-1]) + (hours * 3600.0 - self.total_time)).strftime('%X')
  end

  def last_entry
    @entries[-1]
  end
end

def parse_row(line)
  row = line.chomp.split(/\s{2,}|\t/)
  message = row[-1]
  entries = row[2..-2]
  if row[-1] =~ /^\d{2}:\d{2}:\d{2}$/
    message = ''
    entries = row[2..-1]
  end
  EntryRow.new(row[0], row[1], entries, message)
end

lines = File.readable?(filename) ? File.open(filename).readlines : []
match = []

if options[:print]
  match = lines.grep(/^[-\d]*#{options[:print]}/)
elsif options[:quitting]
  match = lines.grep(/^#{date}/)
  row = match[0]
  unless row
    puts 'You must have started the day to calculate quitting time.'
    exit
  end
  row = parse_row(row)
  
  unless row.is_currently_working?
    puts 'You must be currently working to calculate quitting time.'
    exit
  end

  match = row.quitting_time(options[:quitting])
elsif options[:message]
  match = lines.grep(/^#{date}/) do |line|
    row = parse_row(line)
    row.message = options[:message]
    line.replace(row.to_line)
  end

  if match.empty?
    match << EntryRow.new(date, '0.0', [], options[:message]).to_line
    lines << match[0]
  end
elsif options[:repair]
  lines.each do |line|
    line.replace(parse_row(line).to_line)
  end
elsif options[:undo]
  row = parse_row(lines[-1])
  row.pop_entry
  match = row.to_line

  lines[-1].replace(match)

elsif options[:list]
  match = lines[-options[:count]..lines.length].join
else
  match = lines.grep(/^#{date}/) do |line|
    row = parse_row(line)
    row.add_entry(time)
    line.replace(row.to_line)
  end

  if match.empty?
    match << EntryRow.new(date, '0.0', [time], '').to_line
    lines << match[0]
  end
end

File.open(filename, 'w').puts lines if options[:save]
puts match
