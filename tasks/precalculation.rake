# desc "Will examine the aggregate table stack desribed in aggregations.rb and execute sql to populate data from the base table.
# If run without arguments the entire table stack will be truncated and repopulated. In order to limit the scope of a paticular update please envoke as follows:
# rake db:aggregate 'date > 2008-01-01'
# will only replace data with a date of 2008 or greater in tables with a date dimension. Tables without a date dimension will be truncated and recalculated from scratch."

def precalculate_dir
  File.join(RAILS_ROOT,'db','precalculate')
end

namespace :db do
  desc "Performs aggregations specified in the files in the db/precalculate directory"
  task :precalculate, :where, :needs => [:environment] do |t, args|
    ActiveRecord::Precalculator.precalculate(precalculate_dir, args.where)
  end
end

namespace :precalculate do
  namespace :config do
    task :edit => :environment do
      
      
      begin
      puts "\nPlease enter the ActiveRecord subclass for which you want to define calculations."
      puts "You should have already run `ruby script/generate precalculation <subclass_name>`."
      puts "Run `ruby script/generate precalculation` outside this helper for information."
      print "Class name: "
      active_record = STDIN.gets.chomp.camelize.constantize
      rescue
        puts "\nError! That class name was not recognized."
        retry
      end
      begin
      print "Table name: "
      table_name = STDIN.gets.chomp.underscore
      precalculation_class = ActiveRecord::Precalculation.defined_for active_record
      precalculation = precalculation_class.new :table_name => table_name
      rescue
        puts "\nError! Perhaps that table name is already being used?"
        retry
      end
      puts <<-EOV
      
Please enter the field descriptors on separate lines below.
Each descriptor should be either the name of a base table dimension column
or an operation and a fact column separated with an underscore.
  eg. `dimensioncolumn` or `sum_factcolumn`
Type the column alias after the descriptor (separated with a colon) 
if you want a column name other than the default.
  eg. `count_distinct_customer_id:Customers #`

Type `exit` when you have finished entering all your fields.
EOV
      while line = STDIN.gets.chomp
        break if line =~ /^exit$/
        field_name, name = line.split(':')
        begin
        precalculation.field field_name, (name ? {:alias => name} : {})
        rescue
          puts "\nError! Field definition '#{field_name}' could not be parsed and will be ignored."
        end
      end
      configuration = File.readlines(File.join(precalculate_dir, "#{active_record.to_s.underscore}_precalculation.rb"))
      line = configuration.index configuration.detect { |line| line =~ Regexp.new("class #{active_record.to_s}Precalculation") } || 0
      configuration.insert line+1, "\n" + precalculation.to_config

      File.open(File.join(precalculate_dir, "#{active_record.to_s.underscore}_precalculation.rb"), 'w').write(configuration)
      puts <<-EOV
      
The configuration file has been updated with your changes.
Please check the file and make any neccessary alterations before running `rake precalculate:config:commit` to confirm changes.

EOV
    end
  
    task :commit do
      Dir.chdir precalculate_dir
      `git commit -a -m 'Precalculate auto-commit'`
      puts 'Config file(s) committed! Restart the server for changes to take effect.'
    end
    
    task :rollback do
      puts 'This will undo any uncommitted changes. Are you sure? (y/n)'
      if STDIN.gets.chomp =~ /y/i
        Dir.chdir precalculate_dir
        `git reset --hard`
        puts 'Config rolled back to last commit. Subsequent changes have been lost.'
      else
        puts 'Exiting'
      end
    end
    
    task :test => :environment do
      FileList.new("#{RAILS_ROOT}/vendor/plugins/precalculation/lib/active_record/*").each { |file| load file }
      tests_passed = true 
      Dir.glob(File.join(precalculate_dir, '*.rb')).each do |file|
        puts <<-EOV
        
Testing #{file} ...
EOV
        begin
          load file
        rescue => error
          puts <<-EOV
Error in configuration detected: #{error.message}

EOV
          tests_passed = false
        else
          puts <<-EOV
Configuration parsed successfully!

EOV
        end
      end
    end
    
  end
end
