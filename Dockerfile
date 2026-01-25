# TruffleRuby Native with JFR streaming support
# Built from https://github.com/lbarasti/truffleruby/releases/tag/v34.0.0-dev-jfr
FROM debian:stable-slim AS base

ENV LANG=C.UTF-8
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH=$GEM_HOME/bin:/usr/local/bin:$PATH

RUN set -eux ;\
    apt-get update ;\
    apt-get install -y --no-install-recommends \
            make gcc g++ \
            ca-certificates \
            libz-dev \
            tar \
            wget \
    ; \
    rm -rf /var/lib/apt/lists/* ;\
    case "$(uname -m)" in \
      x86_64) arch="x64" ;; \
      aarch64) arch="aarch64" ;; \
    esac; \
    wget -q https://github.com/lbarasti/truffleruby/releases/download/v34.0.0-dev-jfr/truffleruby-jfr-34.0.0-dev-linux-$arch.tar.gz ;\
    tar -xzf truffleruby-jfr-34.0.0-dev-linux-$arch.tar.gz -C /usr/local ;\
    rm truffleruby-jfr-34.0.0-dev-linux-$arch.tar.gz ;\
    /usr/local/lib/truffle/post_install_hook.sh ;\
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
