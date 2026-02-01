# TruffleRuby Native installed via ruby-build
FROM debian:stable-slim AS base

ENV LANG=C.UTF-8
ENV TRUFFLERUBY_HOME=/opt/truffleruby
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH=$GEM_HOME/bin:$TRUFFLERUBY_HOME/bin:$PATH

RUN set -eux ;\
    apt-get update ;\
    apt-get install -y --no-install-recommends \
            make gcc g++ \
            ca-certificates \
            libz-dev \
            curl \
    ; \
    # Install mise (fast Ruby version manager)
    curl https://mise.run | sh ;\
    export PATH="/root/.local/bin:$PATH" ;\
    # Install TruffleRuby dev (fast: ~5 seconds, no compilation needed)
    mise install ruby@truffleruby-dev ;\
    ln -s /root/.local/share/mise/installs/ruby/truffleruby-dev $TRUFFLERUBY_HOME ;\
    # Cleanup
    rm -rf /var/lib/apt/lists/* ;\
    ruby --version ;\
    gem --version ;\
    bundle --version ;\
    mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENV RACK_ENV=production

EXPOSE 8080

CMD ["ruby", "app.rb"]
