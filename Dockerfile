# Meets: one image that serves the Flutter web app and the Dart API.
#
#   docker build -t meets .
#   docker run -p 8080:8080 -e QLOO_API_KEY=... -e ANTHROPIC_API_KEY=... meets

# ---- build: Flutter web + native server binary --------------------------------
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.5
ARG FLUTTER_SHA256=2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" FLUTTER_SUPPRESS_ANALYTICS=true
RUN flutter config --no-analytics >/dev/null && flutter precache --web

WORKDIR /src
COPY packages/meets_core/pubspec.* packages/meets_core/
COPY server/pubspec.* server/
COPY app/pubspec.* app/
RUN cd packages/meets_core && dart pub get && cd /src/server && dart pub get && cd /src/app && flutter pub get
COPY packages packages
COPY server server
COPY app app
RUN cd app && flutter build web --release --no-web-resources-cdn
RUN cd server && dart compile exe bin/server.dart -o /out/meets-server

# ---- runtime ------------------------------------------------------------------
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* && useradd --create-home meets
WORKDIR /srv
COPY --from=build /out/meets-server /srv/meets-server
COPY --from=build /src/app/build/web /srv/web
COPY server/examples /srv/examples
RUN mkdir -p /srv/data && chown -R meets /srv/data
USER meets
ENV PORT=8080 HOST=0.0.0.0 WEB_DIR=/srv/web EXAMPLES_DIR=/srv/examples DATA_DIR=/srv/data
EXPOSE 8080
CMD ["/srv/meets-server"]
