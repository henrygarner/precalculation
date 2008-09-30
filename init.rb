require 'active_record/precalculation.rb'
Dir.glob(File.join(RAILS_ROOT, 'db', 'precalculate', '*.rb')).each {|f| require f }

ActiveRecord::Base.class_eval { include ActsAsPrecalculated }
