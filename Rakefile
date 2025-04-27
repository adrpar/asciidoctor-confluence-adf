require 'rake'
require 'rake/testtask'

# Define the default task
task :default => [:test]

# Define a task for running tests
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
end

# Define a task for building the project
task :build do
  puts 'Building the Asciidoctor converter plugin...'
  # Add build steps here
end

# Define a task for cleaning up build artifacts
task :clean do
  puts 'Cleaning up build artifacts...'
  # Add cleanup steps here
end

# Define a task for running the plugin
task :run do
  puts 'Running the Asciidoctor converter plugin...'
  # Add run steps here
end

# Define a task for installing dependencies
task :install do
  puts 'Installing dependencies...'
  sh 'bundle install'
end