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
    '--vm.XX:+FlightRecorder',
    'jfr_streaming_test.rb'
end

task default: :server
