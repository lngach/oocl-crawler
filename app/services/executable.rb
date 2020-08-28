module Executable
    extend ActiveSupport::Concern
  
    class_methods do
      def execute(*args)
        new(*args).execute
      end
    end
end