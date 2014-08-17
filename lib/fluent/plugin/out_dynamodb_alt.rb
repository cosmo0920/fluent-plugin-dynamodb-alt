class Fluent::DynamodbAltOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('dynamodb_alt', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin

  unless method_defined?(:log)
    define_method('log') { $log }
  end

  config_param :profile,              :string,  :default => nil
  config_param :credentials_path,     :string,  :default => nil
  config_param :aws_key_id,           :string,  :default => nil
  config_param :aws_sec_key,          :string,  :default => nil
  config_param :region,               :string,  :default => nil
  config_param :table_name,           :string,  :default => nil
  config_param :timestamp_key,        :string,  :default => 'time'
  config_param :concurrency,          :integer, :default => 1
  config_param :use_update_item,      :bool,    :default => false
  config_param :expected,             :string,  :default => nil
  config_param :conditional_operator, :string,  :default => 'AND'

  config_set_default :include_time_key, true
  config_set_default :include_tag_key,  true

  def initialize
    super
    require 'aws-sdk-core'
    require 'parallel'
  end

  def configure(conf)
    super

    unless @table_name
      raise ConfigError, "'#{@table_name}' is required"
    end

    aws_opts = {}

    if @profile
      credentials_opts = {:profile_name => @profile}
      credentials_opts[:path] = @credentials_path if @credentials_path
      credentials = Aws::SharedCredentials.new(credentials_opts)
      aws_opts[:credentials] = credentials
    end

    aws_opts[:access_key_id] = @aws_key_id if @aws_key_id
    aws_opts[:secret_access_key] = @aws_sec_key if @aws_sec_key
    aws_opts[:region] = @region if @region

    Aws.config.update(aws_opts)

    client = Aws::DynamoDB::Client.new
    table = client.describe_table(:table_name => @table_name)

    table.table.key_schema.each do |attribute|
      case attribute.key_type
      when 'HASH'
        @hash_key = attribute.attribute_name
      when 'RANGE'
        @range_key = attribute.attribute_name
      else
        raise 'must not happen'
      end
    end

    if @expected
      @expected = parse_expected(@expected)
      log.info("dynamodb_alt expected: #{@expected.inspect}")
    end
  rescue => e
    raise Fluent::ConfigError, e.message
  end

  def start
    super

    @client = Aws::DynamoDB::Client.new
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    chunk = aggregate_sessions(chunk)
    block = proc do |tag, time, record|
      put_record(record)
    end

    if @concurrency > 1
      Parallel.each(chunk, :in_threads => @concurrency, &block)
    else
      chunk.each(&block)
    end
  end

  private

  def put_record(record)
    if validate_record(record)
      item = {
        :table_name => @table_name,
        :item => record
      }

      begin
        if @expected
          expected = create_expected(record)
          return unless expected
          item[:expected] = expected
          item[:conditional_operator] = @conditional_operator if expected.length > 1
        end

        @client.put_item(item)
      rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException, Aws::DynamoDB::Errors::ValidationException => e
        log.warn("#{e.message}: #{item.inspect}")
      end
    end
  end

  def validate_record(record)
    if not record[@hash_key]
      log.warn("Hash Key '#{@hash_key}' does not exist in the record: #{record.inspect}")
      return false
    end

    if @range_key and not record[@range_key]
      log.warn("Range Key '#{@range_key}' does not exist in the record: #{record.inspect}")
      return false
    end

    if not record[@timestamp_key]
      log.warn("Timestamp '#{@timestamp_key}' does not exist in the record: #{record.inspect}")
      return false
    end

    return true
  end

  def parse_expected(expected)
    expected.split(',').map do |expr|
      key, op, val = expr.strip.split(/\s+/)

      if val
        if val =~ /\A\$\{(.+)\}\z/
          record_key = $1.inspect
          val = eval("proc {|record| record[#{record_key}] }")
        else
          val = JSON.parse("[#{val}]").first if val
        end
      end

      [key, op, val]
    end
  end

  def create_expected(record)
    attrs = {}

    @expected.map do |key, op, val|
      attrs[key] = {:comparison_operator => op}

      if val
        if val.kind_of?(Proc)
          record_val = val.call(record)

          unless record_val
            log.warn("Expected value does not exist in the record: #{record.inspect}")
            return nil
          end

          attrs[key][:attribute_value_list] = [record_val]
        else
          attrs[key][:attribute_value_list] = [val]
        end
      end
    end

    return attrs
  end

  def aggregate_sessions(chunk)
    chunk.enum_for(:msgpack_each).chunk {|tag, time, record|
      if @range_key
        record.values_at(@hash_key, @range_key)
      else
        record[@hash_key]
      end
    }.map {|primary_key, records|
      records.sort_by {|tag, time, record|
        record[@timestamp_key]
      }.last
    }
  end
end