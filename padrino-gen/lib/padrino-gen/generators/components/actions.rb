module Padrino
  module Generators
    module Components
      module Actions
        BASE_TEST_HELPER = (<<-TEST).gsub(/^ {8}/, '')
        RACK_ENV = 'test' unless defined?(RACK_ENV)
        require File.dirname(__FILE__) + "/../config/boot"
        Bundler.require_env(:testing)
        TEST

        # Adds all the specified gems into the Gemfile for bundler
        # require_dependencies 'activerecord'
        # require_dependencies 'mocha', 'bacon', :only => :testing
        def require_dependencies(*gem_names)
          options = gem_names.extract_options!
          gem_names.reverse.each { |lib| insert_into_gemfile(lib, options) }
        end

        # Inserts a required gem into the Gemfile to add the bundler dependency
        # insert_into_gemfile(name)
        # insert_into_gemfile(name, :only => :testing, :require_as => 'foo')
        def insert_into_gemfile(name, options={})
          after_pattern = options[:only] ? "#{options[:only].to_s.capitalize} requirements\n" : "Component requirements\n"
          gem_options = options.slice(:only, :require_as).collect { |k, v| "#{k.inspect} => #{v.inspect}" }.join(", ")
          include_text = "gem '#{name}'" << (gem_options.present? ? ", #{gem_options}" : "") << "\n"
          options.merge!(:content => include_text, :after => after_pattern)
          inject_into_file('Gemfile', options[:content], :after => options[:after])
        end

        # For orm database components
        # Generates the model migration file created when generating a new model
        # options => { :base => "....text...", :up => "..text...",
        #             :down => "..text...", column_format => "t.column :#{field}, :#{kind}" }
        def output_model_migration(filename, name, columns, options={})
          model_name = name.to_s.pluralize
          field_tuples = fields.collect { |value| value.split(":") }
          field_tuples.collect! { |field, kind| kind =~ /datetime/i ? [field, 'DateTime'] : [field, kind] } # fix datetime
          column_declarations = field_tuples.collect(&options[:column_format]).join("\n      ")
          contents = options[:base].dup.gsub(/\s{4}!UP!\n/m, options[:up]).gsub(/!DOWN!\n/m, options[:down])
          contents = contents.gsub(/!NAME!/, model_name.camelize).gsub(/!TABLE!/, model_name.underscore)
          contents = contents.gsub(/!FILENAME!/, filename.underscore).gsub(/!FILECLASS!/, filename.camelize)
          current_migration_number = Dir[app_root_path('db/migrate/*.rb')].map { |f| 
            File.basename(f).match(/^(\d+)/)[0].to_i }.max.to_i || 0
          contents = contents.gsub(/!FIELDS!/, column_declarations).gsub(/!VERSION!/, (current_migration_number + 1).to_s)
          migration_filename = "#{format("%03d", current_migration_number+1)}_#{filename.underscore}.rb"
          create_file(app_root_path('db/migrate/', migration_filename), contents)
        end

        # For orm database components
        # Generates a standalone migration file based on the given options and columns
        # options => { :base "...text...", :change_format => "...text...",
        #              :add => lambda { |field, kind| "add_column :#{table_name}, :#{field}, :#{kind}" },
        #              :remove => lambda { |field, kind| "remove_column :#{table_name}, :#{field}" }
        def output_migration_file(filename, name, columns, options={})
          change_format = options[:change_format]
          migration_scan = filename.camelize.scan(/(Add|Remove)(?:.*?)(?:To|From)(.*?)$/).flatten
          direction, table_name = migration_scan[0].downcase, migration_scan[1].downcase.pluralize if migration_scan.any?
          tuples = direction ? columns.collect { |value| value.split(":") } : []
          tuples.collect! { |field, kind| kind =~ /datetime/i ? [field, 'DateTime'] : [field, kind] } # fix datetime
          add_columns    = tuples.collect(&options[:add]).join("\n    ")
          remove_columns = tuples.collect(&options[:remove]).join("\n    ")
          forward_text = change_format.gsub(/!TABLE!/, table_name).gsub(/!COLUMNS!/, add_columns) if tuples.any?
          back_text    = change_format.gsub(/!TABLE!/, table_name).gsub(/!COLUMNS!/, remove_columns) if tuples.any?
          contents = options[:base].dup.gsub(/\s{4}!UP!\n/m,   (direction == 'add' ? forward_text.to_s : back_text.to_s))
          contents.gsub!(/\s{4}!DOWN!\n/m, (direction == 'add' ? back_text.to_s : forward_text.to_s))
          contents = contents.gsub(/!FILENAME!/, filename.underscore).gsub(/!FILECLASS!/, filename.camelize)
          current_migration_number = Dir[app_root_path('db/migrate/*.rb')].map { |f| 
            File.basename(f).match(/^(\d+)/)[0].to_i }.max.to_i || 0
         contents.gsub!(/!VERSION!/, (current_migration_number + 1).to_s)
          migration_filename = "#{format("%03d", current_migration_number+1)}_#{filename.underscore}.rb"
          # migration_filename = "#{Time.now.strftime("%Y%m%d%H%M%S")}_#{filename.underscore}.rb"
          create_file(app_root_path('db/migrate/', migration_filename), contents)
        end

        # For testing components
        # Injects the test class text into the test_config file for setting up the test gen
        # insert_test_suite_setup('...CLASS_NAME...')
        # => inject_into_file("test/test_config.rb", TEST.gsub(/CLASS_NAME/, @class_name), :after => "set :environment, :test")
        def insert_test_suite_setup(suite_text, options={})
          test_helper_text = [BASE_TEST_HELPER, suite_text.gsub(/CLASS_NAME/, @class_name)].join("\n")
          options.reverse_merge!(:path => "test/test_config.rb")
          create_file(options[:path], test_helper_text)
        end

        # For mocking components
        # Injects the mock library include into the test class in test_config for setting up mock gen
        # insert_mock_library_include('Mocha::API')
        # => inject_into_file("test/test_config.rb", "  include Mocha::API\n", :after => /class.*?\n/)
        def insert_mocking_include(library_name, options={})
          options.reverse_merge!(:indent => 2, :after => /class.*?\n/, :path => "test/test_config.rb")
          return unless File.exist?(File.join(self.destination_root, options[:path]))
          include_text = indent_spaces(options[:indent]) + "include #{library_name}\n"
          inject_into_file(options[:path], include_text, :after => options[:after])
        end

        # Returns space characters of given count
        # indent_spaces(2)
        def indent_spaces(count)
          ' ' * count
        end
        
        # For Controller action generation
        # Takes in fields for routes in the form of get:index post:test delete:yada and such
        def controller_actions(fields)
          field_tuples = fields.collect { |value| value.split(":") }
          action_declarations = field_tuples.collect do |request, name| 
            "#{request} :#{name} do\n  end\n"
            end.join("\n  ")
        end
        
        # For controller route generation
        # Takes in the fields and maps out an appropriate default route.
        # where controller is user and route is get:test, will add map(:test).to("/user/test")
        def controller_routes(name,fields)
          field_tuples = fields.collect { |value| value.split(":") }
          routes = "\n" + field_tuples.collect do |request, route| 
            "  map(:#{route}).to(\"/#{name}/#{route}\")"
            end.join("\n") + "\n"
        end
        
      end
    end
  end
end