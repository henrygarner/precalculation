# desc "Will examine the aggregate table stack desribed in aggregations.rb and execute sql to populate data from the base table.
# If run without arguments the entire table stack will be truncated and repopulated. In order to limit the scope of a paticular update please envoke as follows:
# rake db:aggregate 'date > 2008-01-01'
# will only replace data with a date of 2008 or greater in tables with a date dimension. Tables without a date dimension will be truncated and recalculated from scratch."
namespace :db do
  desc "Performs aggregations specified in the files in the db/precalculate directory"
  task :precalculate, :where, :needs => ['precalculate:commit_config', :environment] do |t, args|
    ActiveRecord::Precalculator.precalculate('db/precalculate/', args.where)
  end
  
end

namespace :precalculate do
  
  namespace :commit do
    task :config do
    end
  end
  
  namespace :test do
    task :config do
      load("#{RAILS_ROOT}/vendor/plugins/precalculation/lib/active_record/precalculation.rb")
      Dir.glob(File.join(RAILS_ROOT, 'db', 'precalculate', '*.rb')).each do |file|
        puts "=== Loading #{file} ==="
        begin
          load file
        rescue => error
          puts "ERROR in configuration detected: #{error.message}"
        else
          puts "Configuration parsed successfully!"
        end
        puts "=== Loading #{file} ===".gsub(/./, '=')
      end
    end
  end
  
end
