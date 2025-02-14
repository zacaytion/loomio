namespace :loomio do
  task generate_test_error: :environment do
    raise "this is a generated test error"
  end

  task :version do
    puts Loomio::Version.current
  end

  task update_blocked_domains: :environment do
    UpdateBlockedDomainsWorker.perform_async
  end

  task generate_email_icons: :environment do
    colors = AppConfig.colors.flatten.flatten.filter {|c| c.starts_with?("#")}.map {|c| c[1..-1]}
    source_path = Rails.root.join("app", "assets", "images", "icons", "svgs", "*.svg").to_s
    dest_path = Rails.root.join("app", "assets", "images", "icons")

    Dir[source_path].each do |path|
      original = File.read(path)
      basename = File.basename(path).split(".").first
      document = Nokogiri::XML.parse(original)
      Dir.chdir(dest_path) do
        colors.each do |color|
          current = document.dup
          # current.css('svg').first.set_attribute 'viewBox', "0 0 96 96"
          current.css("path:not([fill])").set(:fill, "##{color}")
          im = Vips::Image.new_from_buffer(current.to_s, "", {scale: 8})
          im.write_to_file dest_path.to_s+"/#{basename}-#{color}.png"
        end
      end 
    end
  end
  
  task generate_static_error_pages: :environment do
    [400, 404, 403, 410, 417, 422, 429, 500].each do |code|
      ['html'].each do |format|
        File.open("public/#{code}.#{format}", "w") do |f|
          if format == "html"
            f << "<!-- This file is automatically generated by rake loomio:generate_static_error_pages -->\n"
            f << "<!-- Don't make changes here; they will be overwritten. -->\n"
          end
          f << ApplicationController.new.render_to_string(
            locals: {
              '@title': I18n.t("errors.#{code}.title"),
              '@body': I18n.t("errors.#{code}.body"),
            },
            template: "application/error",
            layout: "basic",
            format: format
          )
        end
      end
    end
  end

  task hourly_tasks: :environment do
    ThrottleService.reset!('hour')
    PollService.delay.expire_lapsed_polls
    PollService.delay.publish_closing_soon
    TaskService.delay.send_task_reminders

    SendDailyCatchUpEmailWorker.perform_async

    if (Time.now.hour == 0)
      ThrottleService.reset!('day')
      
      Group.expired_demo.delete_all
      DemoService.delay.generate_demo_groups 

      CleanupService.delay.delete_orphan_records
      OutcomeService.delay.publish_review_due
      LoginToken.where("created_at < ?", 24.hours.ago).delete_all
      ReceivedEmailService.delay.delete_old_emails
    end

    DemoService.delay.ensure_queue
    
    if (Time.now.hour == 0 && Time.now.mday == 1)
      UpdateBlockedDomainsWorker.perform_async
    end
  end

  task generate_error: :environment do
    raise "this is an exception to test exception handling"
  end

  task publish_system_notice: :environment do
    MessageChannelService.publish_system_notice(ENV['LOOMIO_SYSTEM_NOTICE'])
  end

  task update_subscription_members_counts: :environment do
    SubscriptionService.update_member_counts
  end

  task refresh_expiring_chargify_management_links: :environment do
    # run this once a week
    if Date.today.sunday?
      SubscriptionService.delay.refresh_expiring_management_links
    end
  end

  task populate_chargify_management_links: :environment do
    if Date.today.sunday?
      SubscriptionService.delay.populate_management_links
    end
  end

end
