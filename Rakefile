desc 'Run the server'
task :server do
  exec 'ruby', 'app.rb'
end

desc 'Run the server with JFR recording enabled'
task :jfr do
  jfr_file = ENV.fetch('JFR_FILE', 'recording.jfr')
  exec 'ruby', "--vm.XX:StartFlightRecording=filename=#{jfr_file},dumponexit=true", 'app.rb'
end

desc 'Test JFR streaming'
task :jfr_streaming do
  exec 'ruby',
    'jfr_streaming_test.rb'
end

TRUFFLERUBY_NATIVE = '/Users/lorenzobarasti/.rvm/rubies/truffleruby-34.0.0-dev/bin/'

desc 'Run with TruffleRuby native (clears gem path conflicts)'
task :truffleruby do
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  ENV['PATH'] = "#{TRUFFLERUBY_NATIVE}:#{ENV['PATH']}"
  exec "#{TRUFFLERUBY_NATIVE}/ruby", 'app.rb'
end

desc 'Bundle install for TruffleRuby native'
task 'truffleruby:install' do
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  ENV['PATH'] = "#{TRUFFLERUBY_NATIVE}:#{ENV['PATH']}"
  exec "#{TRUFFLERUBY_NATIVE}/bundle", 'install'
end

RUBY4 = '/Users/lorenzobarasti/.rvm/rubies/ruby-4.0.1/bin/'

desc 'Run with Ruby 4'
task :ruby4 do
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  ENV['PATH'] = "#{RUBY4}:#{ENV['PATH']}"
  exec "#{RUBY4}/ruby", 'app.rb'
end

desc 'Bundle install for Ruby 4'
task 'ruby4:install' do
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  ENV['PATH'] = "#{RUBY4}:#{ENV['PATH']}"
  exec "#{RUBY4}/bundle", 'install'
end

task default: :server
