# TruffleRuby Metrics Demo

A Sinatra app demonstrating real-time system metrics with TruffleRuby Native, deployed on Fly.io.

## Live Demo

https://truffleruby-jfr-demo.fly.dev/

## Architecture

```
app.rb
├── SystemMetrics module    → /proc (Linux) or top/vm_stat/ps (macOS)
├── Metrics module          → ring buffer (60 entries max)
├── Background thread       → samples metrics every 1s
├── GET /                   → redirects to /dashboard
├── GET /compute?n=N        → CPU-bound prime counting
├── GET /dashboard          → Chart.js real-time dashboard
├── GET /events             → SSE stream of metrics
└── GET /health             → health check endpoint
```

## Key Design Decisions

1. **Native TruffleRuby** (not JVM mode) - fast startup (~2s) vs 5+ min for JVM
2. **System metrics via /proc or shell** - JFR streaming API requires JVM mode; on macOS uses `top`, `vm_stat`, `ps`
3. **No Mutex** - TruffleRuby 33 Hash is thread-safe
4. **SSE for real-time updates** - dashboard polls /events every second
5. **Sinatra classic mode** - simple, single-file app

## Local Development

```bash
bundle install
rake server    # or just: rake
# Visit http://localhost:8080
```

### With JFR enabled

```bash
rake jfr
# Or with custom file: JFR_FILE=/tmp/recording.jfr rake jfr
```

JFR recording is written on graceful shutdown. Analyze with `jfr print recording.jfr` or VisualVM.

## Deploy to Fly.io

```bash
fly deploy
```

## Files

| File | Purpose |
|------|---------|
| `app.rb` | Main Sinatra app with metrics collection |
| `views/dashboard.erb` | Real-time charts (Chart.js + SSE) |
| `Rakefile` | Tasks: `server` (default), `jfr` (with JFR recording) |
| `Dockerfile` | TruffleRuby 33 native standalone on Debian |
| `fly.toml` | Fly.io deployment config |
| `Gemfile` | Dependencies: sinatra, puma, rackup, json |
| `config.ru` | Rack config |

## Known Issues / TODOs

- [ ] JFR only available on exit (no mid-flight dumps in native mode without custom build)
- [ ] `jdk.CPULoad` not supported in GraalVM Native Image
- [ ] Sinatra's `host_authorization` must be disabled for Fly.io (see [#2065](https://github.com/sinatra/sinatra/issues/2065))

## References

- [GraalVM Native Image JFR Support](https://github.com/oracle/graal/issues/5410)
- [TruffleRuby Releases](https://github.com/oracle/truffleruby/releases)
- [Sinatra Host Authorization Issue](https://github.com/sinatra/sinatra/issues/2065)
