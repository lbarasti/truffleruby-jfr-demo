# TruffleRuby JVM mode - based on official stable.dockerfile pattern
FROM buildpack-deps:stable

ENV LANG=C.UTF-8
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
    BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH=$GEM_HOME/bin:$PATH

ARG TRUFFLERUBY_VERSION=33.0.1

# Install TruffleRuby JVM standalone (includes JFR support)
RUN set -eux ;\
    case "$(uname -m)" in \
      x86_64) arch="amd64" ;; \
      aarch64) arch="aarch64" ;; \
    esac; \
    wget -q https://github.com/truffleruby/truffleruby/releases/download/graal-$TRUFFLERUBY_VERSION/truffleruby-community-jvm-$TRUFFLERUBY_VERSION-linux-$arch.tar.gz ;\
    tar -xzf truffleruby-community-jvm-$TRUFFLERUBY_VERSION-linux-$arch.tar.gz -C /usr/local --strip-components=1 ;\
    rm truffleruby-community-jvm-$TRUFFLERUBY_VERSION-linux-$arch.tar.gz ;\
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
