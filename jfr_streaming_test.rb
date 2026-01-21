# Minimal JFR Event Streaming Example for TruffleRuby
#
# Run with:
#   ruby --experimental-options --ruby.interop-host=true --vm.XX:+FlightRecorder minimal_jfr.rb
#
# ISSUE:
#   Given that GraalVM Native Image supports JFR event streaming
#   (https://www.graalvm.org/latest/reference-manual/native-image/debugging-and-diagnostics/JFR/),
#   it is not possible to use this feature from TruffleRuby because the JFR consumer
#   classes (RecordingStream, FlightRecorder, Recording) are not exposed to the
#   polyglot host access list.
#
# Environment:
#   - TruffleRuby 33.0.0 (Native, not JVM mode)
#   - macOS arm64 (also reproducible on Linux)

puts "TruffleRuby JFR Event Streaming Test"
puts "=" * 50
puts "Ruby: #{RUBY_DESCRIPTION}"
puts

# Test which JFR classes are accessible via Java interop
jfr_classes = [
  'jdk.jfr.Event',
  'jdk.jfr.FlightRecorder',
  'jdk.jfr.Recording',
  'jdk.jfr.consumer.RecordingStream',
  'jdk.jfr.consumer.RecordingFile',
  'jdk.jfr.consumer.EventStream',
]

puts "Testing JFR class accessibility:"
puts "-" * 50

jfr_classes.each do |class_name|
  begin
    klass = Java.type(class_name)
    puts "✓ #{class_name}"

    # Try to check if static methods are accessible
    if Truffle::Interop.has_members?(klass)
      members = Truffle::Interop.members(klass).to_a
      puts "  Members: #{members.join(', ')}"
    end
  rescue => e
    puts "✗ #{class_name}"
    puts "  Error: #{e.message}"
  end
end

puts
puts "-" * 50
puts "Attempting to create RecordingStream..."
puts "-" * 50

begin
  RecordingStream = Java.type('jdk.jfr.consumer.RecordingStream')
  stream = RecordingStream.new

  stream.enable('jdk.CPULoad')
  stream.enable('jdk.GarbageCollection')

  stream.onEvent('jdk.CPULoad') do |event|
    puts "CPU Load event received!"
  end

  stream.startAsync
  puts "SUCCESS: JFR event streaming is working!"

  sleep 5
  stream.close
rescue NameError => e
  puts "FAILED: #{e.class} - #{e.message}"
  puts
  puts "This appears to be a host class access restriction."
  puts "The JFR consumer classes are not exposed to the polyglot context"
  puts "in TruffleRuby's native image build."
rescue => e
  puts "FAILED: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
