# Include hook code here
#require 'active_Record/precalculation.rb'
Dir[File.join RAILS_ROOT, 'db', 'precalculate', '*.rb'].each do |file|
  require file
end 

ActiveRecord::Base.class_eval { include ActsAsPrecalculated }
