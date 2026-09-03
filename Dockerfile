FROM ruby:3.3-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential libsqlite3-dev git curl \
  && rm -rf /var/lib/apt/lists/*

# uv runs pip-audit for bin/scan; install Python now so the first scan does not download it.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python
RUN uv python install 3.12

WORKDIR /app

ENV BUNDLE_WITHOUT=development
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v "$(tail -n1 Gemfile.lock | tr -d ' ')" \
  && bundle install

COPY . .

RUN mkdir -p /app/data
ENV SLA_DATABASE_URL=sqlite:///app/data/sla.sqlite3
EXPOSE 4567
CMD ["bin/server"]
