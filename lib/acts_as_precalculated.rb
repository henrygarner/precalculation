# ActsAsPrecalculated

module ActsAsPrecalculated
  def self.included(base)
    base.extend(ClassMethods)
    base.class_eval do
      sing = class << self; self; end
      sing.send :alias_method_chain, :calculate, :precalculation
    end
  end
  
  module ClassMethods
    
    def calculate_with_precalculation(*args)
      precalculation = ActiveRecord::Precalculation.defined_for self
      if precalculation
        precalculation.results args.flatten
      else
        calculate_without_precalculation *args
      end
    end
    
  end
end
