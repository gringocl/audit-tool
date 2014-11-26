#!/usr/bin/env ruby
# Usage:
#
#   audit-tool <regex>

class RetryError < StandardError; end

require 'bundler/setup'
require 'pp'
Bundler.require

if ARGV.size != 1
  abort "Usage: audit-tool <regex>"
end

regex = ARGV.first

key_prefix = "audit-tool:#{regex}"

redis = Redis.new

search_result = `ag #{regex.inspect}`.strip

matches = search_result.split(/\n+/).map do |line|
  file, line, code = line.match(/^(.+?):(\d+):(.+?)$/)[1..3]

  {
    file: file,
    line: line.to_i,
    code: code
  }
end


CONTEXT = 5

def print_code(match)
  puts match[:file].colorize(:yellow)

  lines = File.read(match[:file]).split("\n")
  lines.unshift("")

  start_context = CONTEXT
  finish_context = CONTEXT

  if match[:line] - start_context < 1
    start_context = 1
  end

  if match[:line] + finish_context > lines.size
    finish_context = lines.size - 1
  end

  start = match[:line] - start_context
  finish = match[:line] + finish_context

  lines[start..finish].each_with_index do |line, index|
    actual_line_num = start + index
    color = actual_line_num == match[:line] ? :red : :white

    print_line(actual_line_num, line, color)
  end
end

def print_line(num, line, color = :white)
  print "#{num}: ".colorize(:green)
  puts line.colorize(color)
end

# audit each line
matches.each_with_index do |match, index|
  redis_key = "#{key_prefix}:#{match[:file]}:#{match[:code]}"

  if redis.exists(redis_key)
    value = redis.get(redis_key)

    if value == 'n' && !ENV.has_key?('IGNORE_NEEDS_FIXING')
      puts "This needs to be fixed:"
      puts
      print_code(match)
      $stdin.gets
    end
  else
    begin
      print_code(match)
      puts
      print "Is this line of code okay? [y/n] ".colorize(:red)
      answer = $stdin.gets.strip.downcase
      puts

      case answer
      when 'y', 'n'
        redis.set(redis_key, answer)
      else
        raise RetryError
      end
    rescue RetryError
      retry
    end
  end
end
