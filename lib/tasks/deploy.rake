# DEPLOYING LOOMIO
# To run a full deploy simply run
# `rake deploy` or `rake deploy:heroku`
#
# This will push the current master branch to production.
# You can change which remote you're pointing to by changing 'HEROKU_REMOTE' in your ENV, default is 'loomio-production'
#
# This deploy script is modular, meaning you can run any part of it individually.
# The order of operations goes:
#
# rake deploy:bump_version    -- add a commit to master which bumps the current version
# rake deploy:plugins:fetch   -- fetch plugins from the loomio_org plugins.yml
# rake deploy:plugins:install -- install plugins so the correct files are built and deployed
# rake deploy:commit          -- commit all non-repository code to a branch for pushing
# rake deploy:push            -- push deploy branch to heroku
# rake deploy:cleanup         -- run rake db:migrate on heroku, restart dynos, and notify clients of version update

# Once per machine, you'll need to run a command to setup heroku
# rake deploy:setup           -- login to heroku and ensure heroku remote is present

def deploy_steps
  [
    "deploy:fetch",
    "deploy:commit",
    "deploy:push",
    "deploy:cleanup"
  ].join(' ')
end

namespace :deploy do
  desc "Deploy to heroku"
  task :heroku do
    puts "Deploying to #{heroku_remote}..."
    run_commands("bundle exec rake #{deploy_steps}")
    at_exit { run_commands("git branch -D #{deploy_branch}") }
  end

  desc "fetch additional stuff"
  task :fetch do
    ['plugins/fetched/loomio_org_plugin','loomio-website'].each do |dir|
      run_commands("rm -rf #{dir}") if Dir.exists?(dir)
    end

    puts "fetching loomio_org_plugin"
    run_commands("git clone -b master git@github.com:loomio/loomio_org_plugin.git plugins/fetched/loomio_org_plugin")
    puts "fetch loomio-website"
    run_commands("git clone -b main git@github.com:loomio/loomio-website.git loomio-website")
    Dir.chdir("loomio-website") do
      run_commands("npm install")
      run_commands("npm run build")
    end
    run_commands("cp -R ./loomio-website/_site/* ./public/")
    run_commands("rm -rf loomio-website")
  end

  desc "Commits built assets to deployment branch"
  task :commit do
    puts "Committing assets to deployment branch..."
    run_commands(
      "git checkout -b #{deploy_branch}",
      "rm -rf plugins/fetched/**/.git",
      "find plugins/fetched -name '*.*' | xargs git add -f",
      "git add -f plugins",
      "git add -f public",
      "git commit -m 'Add marketing plugin only'",
      "git checkout master")
  end

  desc "Push to heroku!"
  task :push, [:remote,:branch,:id] do |t, args|
    puts "Deploying #{deploy_branch} to heroku remote #{heroku_remote}"
    run_commands("git push #{heroku_remote} #{deploy_branch}:master -f")
  end

  desc "Migrate heroku database and restart dynos"
  task :cleanup do
    puts "Migrating heroku..."
    run_commands(
      "#{heroku_cli} run rake db:migrate -a #{heroku_remote}",
      "#{heroku_cli} restart -a #{heroku_remote}"
    )
  end
end

task :deploy => :"deploy:heroku"

def loomio_version
  Loomio::Version.current
end

def deploy_branch
  @deploy_branch ||= "deploy-#{Time.now.to_i}"
end

def heroku_cli
  @heroku_cli ||= `which heroku`.chomp
end

def heroku_plugin_set
  ENV.fetch('HEROKU_PLUGIN_SET', 'loomio_org')
end

def heroku_remote
  ENV.fetch('HEROKU_REMOTE', 'loomio-production')
end

def run_commands(*commands)
  Array(commands).compact.each do |command|
    puts "\n-> #{command}"
    raise "command failed: #{command}" unless system(command)
  end
end
