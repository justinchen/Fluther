module Fluther
  class Config
    def self.fluther_host( *args )
      @@fluther_host = nil  unless defined? @@fluther_host
      return @@fluther_host  if args.empty?
      @@fluther_host = args.first
    end

    def self.app_key( *args )
      @@app_key = nil  unless defined? @@app_key
      return @@app_key  if args.empty?
      @@app_key = args.first
    end

    def self.user_fields( *args )
      @@user_fields = { :id => :id, :name => :name, :email => :email }  unless defined? @@user_fields
      return @@user_fields  if args.empty?
      @@user_fields.update args.first
    end
  end
end
