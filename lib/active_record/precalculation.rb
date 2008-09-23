module ActiveRecord
  class Precalculation
    
    class Field
      attr_accessor :column, :column_alias, :options
      def initialize(column, options={})
        @column_alias = options.delete :alias
        @column, @options = column, options.reverse_merge(:limit => column.limit, :precision => column.precision, :scale => column.scale)
      end
      def select_sql(data_source = nil)
        column_name
      end
      def group_sql
        column_name
      end
      def column_name
        @column.name
      end     
      def type
        @column.type
      end
      def limit
        @column.limit
      end
    end
    
    class Dimension < Field
      
      def select_sql(data_source = nil)
        return "#{column_name}#{ " AS #{column_alias}" if column_name != column_alias }" unless data_source
        if source = source_column(data_source)
          "#{source.column_alias} AS #{column_alias}"
        end
      end
      
      def group_sql(data_source = nil)
        return "#{column_name}" unless data_source
        if source = source_column(data_source)
          "#{source.column_alias}"
        end
      end
      
      def column_alias
        super || column_name
      end
      
      protected
      
      def source_column(data_source)
        data_source.dimensions.detect { |field| field.column_name == column_name }
      end
    end
    
    class Operation < Field
      attr_accessor :operator
      
      def initialize(operator, column, options = {})
        @operator = operator
        super(column, options)
      end
      
      def select_sql(data_source = nil)
        # quick return if our source is the base table
        return "#{operator.to_s.upcase}(#{column_name}) AS #{column_alias}" unless data_source
        
        source = data_source.operations.detect do |field|
          field.column_name == column_name and
          { :sum   => [:sum],
            :min   => [:min],
            :max   => [:max],
            :avg   => [:avg, :sum]
          }[operator].include?(field.operator)
        end
        
        return unless source # Bail with nil if we can't see a way to generate SQL from the data_source
        
        if operator == :avg
          return unless counter = data_source.counters.first
          case source.operator
            when :sum then "SUM(#{source.column_alias}) / SUM(#{counter.column_alias}) AS #{column_alias}"
            when :avg then "SUM(#{source.column_alias} * #{counter.column_alias}) / SUM(#{counter.column_alias}) AS #{column_alias}"
          end
        else
          "#{operator.to_s.upcase}(#{source.column_alias}) AS #{column_alias}"
        end
      end
      
      def group_sql
        nil
      end
      
      def column_alias
        super || "#{operator}_#{column_name}"
      end
      
    end
    
    class Counter
      attr_accessor :options
      def initialize(options = {})
        @column_alias = options.delete :alias
        @options = options
      end
      
      def select_sql(data_source = nil)
        return "COUNT(*) AS #{column_alias}" unless data_source
        if source = data_source.fields.detect { |field| field.is_a? self.class }
          "SUM(#{source.column_alias}) AS #{column_alias}"
        end
      end
      def group_sql
        nil
      end
      def column_alias
        @column_alias || 'count_all'
      end
      def type
        :integer
      end
    end
    
    class << self
      def calculate(table_name, &block)
        calculations << returning(self.new(table_name, &block)) do |obj|
          yield obj
        end
      end
      
      def calculations
        @calculations ||= []
      end
      
      def run!
        calculations.sort { |one,another| one.phase <=> another.phase }.each(&:run!)
      end
    end
    
    attr_accessor :table_name, :fields

    def initialize(table_name)
      @table_name = table_name
    end
    
    def fields
      @fields ||= []
    end
  
    %w(sum min max avg).each do |operation|
      class_eval <<-EOV
        def #{operation}(column_name, options = {})
          fields << Operation.new(:#{operation}, active_record.columns_hash[column_name.to_s], options)
        end
      EOV
    end
    def counter(options = {})
      fields << Counter.new(options)
    end
    alias_method :count, :counter
    
    def self.active_record
      self.inspect =~ (/([A-Z][a-zA-Z]+)Precalculation/)
      $1.constantize
    end
    
    def active_record
      self.class.active_record
    end
    
    def data_source
      # TODO: become smarter about how we pick our data sources.
      # How do we pick when there is more than one to chose from?
      # Lowest column count is a simplistic solution,
      # one which has some idea of row count would be better.
      @data_source ||= (self.class.calculations - [self]).select do |calculation| 
        fields.all? { |field| field.select_sql calculation }
      end.min { |one,another| one.dimensions.size <=> another.dimensions.size }
    end
    
    def run!
      ActiveRecord::Base.connection.execute "DROP TABLE #{table_name}" if ActiveRecord::Base.connection.table_exists?(table_name)
      
      ActiveRecord::Base.connection.create_table table_name, :id => false do |t|
        fields.each do |field|
          t.column field.column_alias, field.type, field.options
        end
      end # unless ActiveRecord::Base.connection.table_exists?(table_name)

      source_table_name = (data_source || active_record).table_name
      
      
      source_fields = fields.collect { |field| field.select_sql(data_source) }
      destination_fields = fields.collect(&:column_alias)
      group = fields.collect(&:group_sql).compact
      
      sql = <<-eov
      INSERT INTO #{table_name} (#{destination_fields.join(', ')})
      SELECT #{source_fields.join(', ')}
      FROM #{source_table_name}
      #{"GROUP BY #{group.join(', ')}" unless group.empty?}
      eov
      
      puts  sql + "\n"
      
      ActiveRecord::Base.connection.execute sql
      
    end
    
    %w(counter operation dimension).each do |field|
      class_eval <<-EOV
        def #{field.pluralize}
          fields.select { |field| field.is_a? #{field.capitalize} }
        end
      EOV
    end
    
    def phase
      data_source ? (data_source.phase + 1) : 1
    end
    
    protected
    
    def method_missing(method_id, *args)
      if active_record.column_names.include? method_id.to_s
        options = args.pop if args.last.is_a?(Hash)
        fields << Dimension.new(active_record.columns_hash[method_id.to_s], options || {})
      else
        super
      end
    end
    
  end
  
  class Precalculator
    class << self
      
      attr_accessor :precalculations
      
      def precalculate(precalculations_path)
        files = Dir["#{precalculations_path}/*.rb"]
        files.collect do |file|
          load(file)
          precalculation = file.match(/([_a-z0-9]*).rb/)[1].classify.constantize
          precalculation.run!
        end
      end
    
    end
  end
  
end