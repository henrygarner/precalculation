class PrecalculationGenerator < Rails::Generator::NamedBase
  
  def manifest
    record do |m|
      m.directory 'db/precalculate'
      m.template 'precalculation.rb', File.join('db/precalculate', "#{file_name}_precalculation.rb"),
        :assigns => { :precalculation_name => "#{class_name}Precalculation" }
    end
  end
  
  protected
  def banner
    "Usage: #{$0} #{spec.name} ModelName"
  end
  
end