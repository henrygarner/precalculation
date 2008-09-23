# Include hook code here
require 'active_Record/precalculation.rb'

ActiveRecord::Base.class_eval { include ActsAsPrecalculated }
