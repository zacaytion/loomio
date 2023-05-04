setup: bundle_install npm_install db_setup rails_install

bundle_config:
	bundle config build.pg --with-pg-config="$(brew --prefix)/opt/libpq/bin/pg_config"

bundle_install: bundle_config
	bundle install

npm_install:
	cd vue
	npm install

rails_install:
	sudo gem install rails -v '6.1.7.3'

db_setup: bundle_install
	# create database
	bundle exec rake db:setup

unit_tests: bundle_install
	bundle exec rspec

public/blient/vue: npm_install
	cd vue
	npm run build

channel_install:
	cd channel_server
	npm install

channel_server_start: channel_install
	cd channel_server
	npm run start > ../log/channel_server.log

install_chromedriver:
	CHROMEDRIVER_VERSION=112.0.5615.49 npm install chromedriver@112.0.0

e2e_tests_setup: install_chromedriver public/blient/vue channel_install

e2e_tests: e2e_tests_setup
	# start channel_server
	cd vue
	npm run test:e2e:standalone

# Artifacts to Use for New Implementation
schema.sql: db_setup
	pg_dump -h localhost -p 5432 -U postgres --clean --schema-only --create -f schema.sql loomio_development

openapi.yml:
	npx @appland/appmap openapi -o openapi.yml

routes.txt:
	bundle exec rails rails routes --expanded > routes.txt
