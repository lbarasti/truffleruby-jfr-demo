# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TruffleRuby Metrics Demo - a Sinatra app demonstrating real-time system metrics with TruffleRuby Native, deployed on Fly.io. Live at https://truffleruby-jfr-demo.fly.dev/

## Commands

```bash
# Install dependencies
bundle install

# Run locally (visit http://localhost:8080/dashboard)
rake server  # or just: rake

# Run with JFR enabled (file written on exit)
rake jfr
# Or with custom path: JFR_FILE=/tmp/recording.jfr rake jfr

# Deploy to Fly.io
fly deploy
```

## Architecture

Single-file Sinatra app (`app.rb`) with two core modules:

- **SystemMetrics**: Reads CPU/memory from `/proc` on Linux, falls back to shell commands on macOS.
- **Metrics**: Thread-safe ring buffer (60 entries max) storing time-series data for cpu, memory, and requests.

A background thread samples system metrics every second. The `/events` endpoint streams this data via SSE to the dashboard. JFR recording is available on exit when enabled via command line.

### Routes

| Endpoint | Purpose |
|----------|---------|
| `/` | Redirects to /dashboard |
| `/mandelbrot?size=N&iter=M` | Generate Mandelbrot fractal PNG (size 64-512, iter 50-500) |
| `/plasma?size=N&scale=F` | Generate plasma/noise pattern PNG (size 64-512) |
| `POST /process` | Process uploaded PNG with filter (grayscale, pixelate, edge) |
| `/dashboard` | Real-time Chart.js dashboard with image generation controls |
| `/events` | SSE stream of metrics snapshot |
| `/health` | Health check returning Ruby version and memory |

## Key Design Decisions

1. **Native TruffleRuby** (not JVM mode) - fast startup (~2s) vs 5+ min for JVM
2. **System metrics via /proc** - JFR streaming API requires JVM mode which has prohibitive startup time
3. **SSE for real-time updates** - dashboard polls /events every second
4. **Sinatra classic mode** - simple, single-file architecture
