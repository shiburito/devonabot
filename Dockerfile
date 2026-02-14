FROM ruby:3.3-alpine AS builder

RUN apk add --no-cache build-base libffi-dev libsodium-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4

FROM ruby:3.3-alpine

RUN apk add --no-cache libffi libsodium gcompat

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

EXPOSE 4567

CMD ["ruby", "app.rb"]
