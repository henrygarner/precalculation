# ActsAsPrecalculated

module ActsAsPrecalculated
  def self.included(base)
    base.extend(ClassMethods)
    base.class_eval do
      sing = class << self; self; end
      sing.send :alias_method_chain, :find, :precalculation
    end
  end
  
  module ClassMethods
    
    def precalculation_table_names
      @precalculation_table_names ||= []
    end
    
    def set_precalculation_table_name(table_name)
      precalculation_table_names << table_name
    end
    
    def find_with_precalculation(*args)
      base_name = self.table_name
      results = nil
      precalculation_table_names.each do |table_name|
        set_table_name table_name
        begin
          puts "attempting query on #{table_name}..."
          results = find_without_precalculation *args
        rescue
          next
        else
          break
        end
      end
      set_table_name(base_name)
      results || find_without_precalculation(*args)
    end
    
  end
end
