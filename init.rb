require 'active_record/precalculation.rb'

Dir.chdir(File.join(RAILS_ROOT, 'db', 'precalculate')) do
  if File.exists? '.git'
    revision = `git show-ref`.split(' ')[0]
    Dir.glob('*.rb').each do |file|
      eval `git show #{revision}:#{file}`
    end
  else
    Dir.glob('*.rb').each {|f| require f }
  end
end

ActiveRecord::Base.class_eval { include ActsAsPrecalculated }
