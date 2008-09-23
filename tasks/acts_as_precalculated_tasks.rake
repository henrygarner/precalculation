# desc "Will examine the aggregate table stack desribed in aggregations.rb and execute sql to populate data from the base table.
# If run without arguments the entire table stack will be truncated and repopulated. In order to limit the scope of a paticular update please envoke as follows:
# rake db:aggregate 'date > 2008-01-01'
# will only replace data with a date of 2008 or greater in tables with a date dimension. Tables without a date dimension will be truncated and recalculated."
namespace :db do
  desc "Performs aggregations specified in the files in the db/precalculate directory"
  task :precalculate => :environment do
    ActiveRecord::Precalculator.precalculate('db/precalculate/')
  end
end
