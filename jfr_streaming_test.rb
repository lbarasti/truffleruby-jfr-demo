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
  puts "✓ RecordingStream class loaded"

  stream = RecordingStream.new
  puts "✓ RecordingStream instance created"

  # Enable multiple event types (use default periods)
  stream.enable('jdk.CPULoad')
  stream.enable('jdk.GarbageCollection')
  puts "✓ Events enabled"

  # Try setting up event callbacks
  cpu_count = 0
  gc_count = 0

  stream.onEvent('jdk.CPULoad') do |event|
    cpu_count += 1
    puts "  CPU Event: jvmUser=#{event.getFloat('jvmUser')}"
  end

  stream.onEvent('jdk.GarbageCollection') do |event|
    gc_count += 1
    puts "  GC Event: cause=#{event.getString('cause')}"
  end
  puts "✓ Callbacks registered"

  # Start recording in async mode
  stream.startAsync
  puts "✓ Stream started in async mode"

  # Do some work to generate events
  puts "Doing some work to generate events..."
  5.times do
    arr = (1..10000).to_a.shuffle
    sleep 0.5
    print "."
  end
  puts

  stream.close
  puts "✓ Stream closed"
  puts "  Events: CPU=#{cpu_count}, GC=#{gc_count}"

  total = cpu_count + gc_count
  puts
  if total > 0
    puts "SUCCESS: JFR event streaming with callbacks works! (#{total} events received)"
  else
    puts "WARNING: Callbacks registered but no events received."
    puts "This might be a threading issue or events are processed differently in native."
  end
rescue NameError => e
  puts "FAILED: #{e.class} - #{e.message}"
  puts
  puts "This appears to be a host class access restriction."
rescue => e
  puts "FAILED: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
