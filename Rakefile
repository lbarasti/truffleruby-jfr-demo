def rvm_bin_for(ruby_version)
  rvm_root = ENV['rvm_path'] || File.join(ENV.fetch('HOME'), '.rvm')
  bin_path = File.join(rvm_root, 'rubies', ruby_version, 'bin')
  return bin_path if Dir.exist?(bin_path)

  abort "Ruby #{ruby_version} is not installed under #{rvm_root}/rubies"
end

def ruby_exec(ruby_version, script_path)
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  exec File.join(rvm_bin_for(ruby_version), 'ruby'), script_path
end

def bundle_exec(ruby_version, *args)
  ENV.delete('GEM_HOME')
  ENV.delete('GEM_PATH')
  exec File.join(rvm_bin_for(ruby_version), 'bundle'), *args
end

desc 'Run the server'
task :server do
  exec 'ruby', './app.rb'
end

desc 'Run the server with JFR recording enabled'
task :jfr do
  jfr_file = ENV.fetch('JFR_FILE', 'recording.jfr')
  exec 'ruby', "--vm.XX:StartFlightRecording=filename=#{jfr_file},dumponexit=true", './app.rb'
end

desc 'Test JFR streaming'
task :jfr_streaming do
  exec 'ruby', './jfr_streaming_test.rb'
end

TRUFFLERUBY_VERSION = 'truffleruby-34.0.0-dev'

desc 'Run with TruffleRuby native (clears gem path conflicts)'
task :truffleruby do
  ENV['PORT'] ||= '8081'
  ruby_exec(TRUFFLERUBY_VERSION, './app.rb')
end

desc 'Bundle install for TruffleRuby native'
task 'truffleruby:install' do
  bundle_exec(TRUFFLERUBY_VERSION, 'install')
end

RUBY4_VERSION = 'ruby-4.0.1'

desc 'Run with Ruby 4'
task :ruby4 do
  ENV['PORT'] ||= '8082'
  ruby_exec(RUBY4_VERSION, './app.rb')
end

desc 'Bundle install for Ruby 4'
task 'ruby4:install' do
  bundle_exec(RUBY4_VERSION, 'install')
end

task default: :server
