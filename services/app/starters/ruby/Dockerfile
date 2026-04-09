FROM ruby:3.3-alpine
WORKDIR /app
COPY Gemfile* ./
RUN bundle install 2>/dev/null || true
COPY . .
USER nobody
EXPOSE 8080
CMD ["ruby", "app.rb"]
