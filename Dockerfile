ARG RUBY_IMAGE
FROM ${RUBY_IMAGE:-ruby:latest}

ARG BUNDLER
ARG RUBYGEMS
RUN echo "--- :ruby: Updating RubyGems and Bundler" \
    && (gem update --system ${RUBYGEMS:-} || gem update --system 3.3.3) \
    && (gem install bundler -v "${BUNDLER:->= 0}" || gem install bundler -v "< 2") \
    && ruby --version && gem --version && bundle --version \
    && codename="$(. /etc/os-release; x="${VERSION_CODENAME-${VERSION#*(}}"; echo "${x%%[ )]*}")" \
    && echo "--- :package: Installing system deps for debian '$codename'" \
    && if [ "$codename" = jessie ]; then \
        # jessie-updates is gone
        sed -i -e '/jessie-updates/d' /etc/apt/sources.list \
        && echo 'deb http://archive.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/backports.list \
        && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/backports-is-unsupported; \
    fi \
    # Pre-requirements
    && if ! which gpg || ! which curl; then \
        apt-get update \
        && apt-get install -y --no-install-recommends \
            gnupg curl; \
    fi \
    # Debian 12 (bookworm) has this directory by default, but older Debian does not
    && mkdir -p /etc/apt/keyrings \
    # Postgres apt sources
    && curl -sS https://www.postgresql.org/media/keys/ACCC4CF8.asc | APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ ${codename}-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    # Node apt sources
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    # Yarn apt sources
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add - \
    && echo "deb http://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
    # Install all the things
    && apt-get update \
    #  buildpack-deps
    && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        bzip2 \
        dpkg-dev \
        file \
        g++ \
        gcc \
        imagemagick \
        libbz2-dev \
        libc6-dev \
        libcurl4-openssl-dev \
        libdb-dev \
        libevent-dev \
        libffi-dev \
        libgdbm-dev \
        libgeoip-dev \
        libglib2.0-dev \
        libjpeg-dev \
        libkrb5-dev \
        liblzma-dev \
        libmagickcore-dev \
        libmagickwand-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libpng-dev \
        libpq-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        libtool \
        libvips-dev \
        libwebp-dev \
        libxml2-dev \
        libxslt-dev \
        libyaml-dev \
        make \
        patch \
        unzip \
        xz-utils \
        zlib1g-dev \
        \
# https://lists.debian.org/debian-devel-announce/2016/09/msg00000.html
        $( \
# if we use just "apt-cache show" here, it returns zero because "Can't select versions from package 'libmysqlclient-dev' as it is purely virtual", hence the pipe to grep
            if apt-cache show 'default-libmysqlclient-dev' 2>/dev/null | grep -q '^Version:'; then \
                echo 'default-libmysqlclient-dev'; \
            else \
                echo 'libmysqlclient-dev'; \
            fi \
        ) \
        $( \
            if apt-cache show 'tzdata-legacy' 2>/dev/null | grep -q '^Version:'; then \
                echo 'tzdata-legacy'; \
            fi \
        ) \
    #  specific dependencies for the rails build
    && apt-get install -y --no-install-recommends \
        postgresql-client default-mysql-client sqlite3 \
        git nodejs=18.19.0-1nodesource1 yarn lsof \
        ffmpeg mupdf mupdf-tools poppler-utils \
    # Install Chrome
    && wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list && \
        apt-get update && apt-get install -y google-chrome-stable \
    # Install ChromeDriver
    && apt-get update && apt-get install -y unzip graphviz && \
        CHROME_VERSION=$(google-chrome-stable --version | cut -d " " -f3) && \
        echo "Chrome_Version: ${CHROME_VERSION}" && \
        curl -sS -o /root/chromedriver_linux64.zip https://storage.googleapis.com/chrome-for-testing-public/$CHROME_VERSION/linux64/chromedriver-linux64.zip &&\
        unzip ~/chromedriver_linux64.zip -d ~/ && \
        rm ~/chromedriver_linux64.zip && \
        chown root:root ~/chromedriver-linux64/chromedriver && \
        chmod 755 ~/chromedriver-linux64/chromedriver && \
        mv ~/chromedriver-linux64/chromedriver /usr/bin/chromedriver \
    # Install Firefox and Geckodriver
    && apt-get update && apt-get install -y --no-install-recommends \
        firefox-esr xvfb \
    && GECKODRIVER_VERSION=$(curl -s https://api.github.com/repos/mozilla/geckodriver/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//') \
    && wget -q https://github.com/mozilla/geckodriver/releases/download/v$GECKODRIVER_VERSION/geckodriver-v$GECKODRIVER_VERSION-linux64.tar.gz \
    && tar -xvzf geckodriver-v$GECKODRIVER_VERSION-linux64.tar.gz -C /usr/local/bin/ \
    && rm geckodriver-v$GECKODRIVER_VERSION-linux64.tar.gz \
    # clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* \
    && mkdir /rails

WORKDIR /rails
ENV RAILS_ENV=test RACK_ENV=test
ENV JRUBY_OPTS="--dev -J-Xmx1024M"

ADD .buildkite/runner /usr/local/bin/
RUN chmod +x /usr/local/bin/runner

# Wildcard ignores missing files; .empty ensures ADD always has at least
# one valid source: https://stackoverflow.com/a/46801962
#
# Essentially, `ADD railties/exe/* railties/exe/` will error if the wildcard doesn't match any files;
# `ADD .buildkite/.empty railties/exe/* railties/exe/` always matches at least one source file, so no error
ADD .buildkite/.empty actioncable/package.jso[n] actioncable/
ADD .buildkite/.empty actiontext/package.jso[n] actiontext/
ADD .buildkite/.empty actionview/package.jso[n] actionview/
ADD .buildkite/.empty activestorage/package.jso[n] activestorage/
ADD .buildkite/.empty package.jso[n] yarn.loc[k] .yarnr[c] ./

RUN rm -f .empty */.empty \
    && find . -maxdepth 1 -type d -empty -exec rmdir '{}' '+' \
    && if [ -f package.json ]; then \
        echo "--- :javascript: Installing JavaScript deps" \
        && yarn install \
        && yarn cache clean; \
    elif [ -f actionview/package.json ]; then \
        echo "--- :javascript: Installing JavaScript deps" \
        && (cd actionview && npm install); \
    fi

ADD */*.gemspec tmp/
ADD .buildkite/.empty tools/*/releaser.gemspec tools/releaser/
ADD .buildkite/.empty railties/exe/* railties/exe/
ADD Gemfile Gemfile.lock RAILS_VERSION rails.gemspec ./

RUN rm -f railties/exe/.empty \
    && find railties/exe -maxdepth 0 -type d -empty -exec rmdir '{}' '+' \
    && echo "--- :bundler: Installing Ruby deps" \
    && (cd tmp && for f in *.gemspec; do d="$(basename -s.gemspec "$f")"; mkdir -p "../$d" && mv "$f" "../$d/"; done) \
    && rm Gemfile.lock && bundle install -j 8 && cp Gemfile.lock tmp/Gemfile.lock.updated \
    && rm -rf /usr/local/bundle/cache \
    && echo "--- :floppy_disk: Copying repository contents"

ADD . ./

RUN mv -f tmp/Gemfile.lock.updated Gemfile.lock \
    && if [ -f package.json ]; then \
        echo "--- :javascript: Building JavaScript package" \
        && if [ -f actionview/package.json ]; then \
            (cd actionview && yarn build); \
        fi \
        && if [ -f railties/test/isolation/assets/package.json ]; then \
            (cd railties/test/isolation/assets && yarn install); \
        fi \
        && yarn cache clean; \
    fi
