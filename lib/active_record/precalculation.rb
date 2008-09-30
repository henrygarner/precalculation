module ActiveRecord
  class Precalculation

    
    class Field
      attr_accessor :column, :column_alias, :options
      def initialize(column, options={})
        @column_alias = options.delete :alias
        @column, @options = column, options.reverse_merge(:limit => column.limit, :precision => column.precision, :scale => column.scale)
      end
      def column_name
        @column.name
      end     
      def type
        @column.type
      end
    end
    
    class Dimension < Field
      
      def select_sql(data_source = nil)
        return "#{column_name}#{ " AS #{column_alias}" if column_name != column_alias }" unless data_source
        if source = source_column(data_source)
          "#{source.column_alias}#{ " AS #{column_alias}" if source.column_alias != column_alias }"
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
        @operator = operator.to_sym
        super(column, options)
      end
      
      def select_sql(data_source = nil)
        # quick return if our source is the base table
        return "#{operator.to_s.upcase}(#{column_name}) AS #{column_alias}" unless data_source
        
        source = data_source.operations.detect do |field|
          field.column_name == column_name and
          { :sum   => [:sum, :avg],
            :min   => [:min],
            :max   => [:max],
            :avg   => [:avg, :sum]
          }[operator].include?(field.operator)
        end
        
        return unless source # Bail with nil if we can't see a way to generate SQL from the data_source
        
        if operator == :avg
          return unless counter = data_source.counters.first
          case source.operator
            when :sum : "SUM(#{source.column_alias}) / SUM(#{counter.column_alias}) AS #{column_alias}"
            when :avg : "SUM(#{source.column_alias} * #{counter.column_alias}) / SUM(#{counter.column_alias}) AS #{column_alias}" end
        elsif [operator, source.operator] == [:sum, :avg]
          return unless counter = data_source.counters.first
          "SUM(#{source.column_alias} * #{counter.column_alias}) AS #{column_alias}"
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
      attr_accessor :conditions, :contingent_column_names, :subclasses
      def precalculate(table_name, &block)
        calculations << returning(self.new(table_name, &block)) do |obj|
          yield obj
        end
      end
      
      def calculations
        @calculations ||= []
      end
      
      def run!(conditions)
        @conditions = conditions
        @contingent_column_names = conditions.to_s.scan(Regexp.new("(#{active_record.column_names.join('|')})", true)).flatten
        calculations.sort { |one,another| one.phase <=> another.phase }.each(&:run!)
      end
      
      def subclasses
        @subclasses ||= []
      end
      
      def inherited(child)
        subclasses << child
      end
      
      def defined_for(active_record)
        subclasses.detect { |child| child.active_record == active_record }
      end
      
      def calculate(*args)
        request = self.new
        args.flatten.each { |from_token| request.field from_token }
        active_record.connection.select_rows request.to_sql
      end
      
    end
    
    attr_accessor :table_name, :fields

    def initialize(table_name = nil)
      @table_name = table_name
    end
    
    def fields
      @fields ||= []
    end
  
    %w(sum min max avg).each do |operation|
      class_eval <<-EOV
        def #{operation}(column_name, options = {})
          field("#{operation}_\#\{column_name\}", options)
        end
      EOV
    end
    
    def counter(options = {})
      field(:counter, options)
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
    
    def phase
      data_source ? (data_source.phase + 1) : 1
    end
    
    %w(counter operation dimension).each do |field|
      class_eval <<-EOV
        def #{field.pluralize}
          fields.select { |field| field.is_a? #{field.capitalize} }
        end
      EOV
    end
    
    def run!
      active_record.transaction do
        Base.connection.table_exists?(table_name) ? prepare_table! : create_table!
        puts "Calculating from '#{(data_source || active_record).table_name}'"
        Base.connection.execute "INSERT INTO #{table_name} (#{fields.collect(&:column_alias).join(', ')})\n#{self.to_sql}"
      end
    end
    
    def to_sql
      source_table_name   = (data_source || active_record).table_name      
      source_fields       = fields.collect { |field| field.select_sql(data_source) }
      group_fields        = fields.collect(&:group_sql).compact
      
      sql= ["SELECT #{source_fields.join(', ')} FROM #{source_table_name}"]
      sql<< "WHERE #{self.class.conditions}" if apply_conditions?
      sql<< "GROUP BY #{group_fields.join(', ')}" unless group_fields.empty?
      sql.join("\n")
    end
    
    def field(descriptor, options={})
      fields << case descriptor = descriptor.to_s
      when /(min|max|sum|avg)_(.*)/i : Operation.new $1, active_record.columns_hash[$2], options
      when /count(er)?/i             : Counter.new options
      else                             Dimension.new active_record.columns_hash[descriptor], options
      end
    end
    
    private
    
    def apply_conditions?
      @apply_conditions ||= self.class.conditions and (self.class.contingent_column_names - dimensions.collect(&:column_name)).empty?
    end
    
    def prepare_table!
      puts "Preparing '#{table_name}'"
      Base.connection.execute apply_conditions? ? "DELETE FROM #{table_name} WHERE #{self.class.conditions}" : "TRUNCATE TABLE #{table_name}"
    end
    
    def create_table!
      puts "Creating '#{table_name}'"
      @apply_conditions = false
      Base.connection.create_table table_name, :id => false do |t|
        fields.each { |field| t.column field.column_alias, field.type, field.options }
      end
    end
    
    def method_missing(method_id, *args)
      if active_record.column_names.include? method_id.to_s
        options = args.pop if args.last.is_a?(Hash)
        field(method_id, options || {})
      else
        super
      end
    end
    
  end
  
  class Precalculator
    class << self
      
      attr_accessor :precalculations
      
      def precalculate(precalculations_path, conditions)
        Precalculation.subclasses.each {|precalculation| precalculation.run!(conditions) }
      end
    
    end
  end
  
end