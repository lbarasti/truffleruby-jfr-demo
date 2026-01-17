FROM debian:bookworm-slim

ARG TRUFFLERUBY_VERSION=33.0.0
ARG TARGETARCH

RUN apt-get update && apt-get install -y curl build-essential libssl-dev zlib1g-dev && \
    ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "amd64") && \
    curl -L -o /tmp/truffleruby.tar.gz \
      "https://github.com/oracle/truffleruby/releases/download/graal-${TRUFFLERUBY_VERSION}/truffleruby-community-${TRUFFLERUBY_VERSION}-linux-${ARCH}.tar.gz" && \
    mkdir -p /opt/truffleruby && \
    tar -xzf /tmp/truffleruby.tar.gz -C /opt/truffleruby --strip-components=1 && \
    rm /tmp/truffleruby.tar.gz && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/truffleruby/bin:$PATH"

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

EXPOSE 8080

CMD ["ruby", "app.rb"]
