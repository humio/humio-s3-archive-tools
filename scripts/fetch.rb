require 'zlib'
require 'stringio'
require 'dotenv/load'
require 'aws-sdk-s3'
require 'ndjson'

errors = []
required_vars = %w{S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_BUCKET_NAME REPO_NAME START_DATE END_DATE}


# If none of the required variables were passed in, assume the user doesn't know about
# them and print them all out for reference.
count = 0
required_vars.each do |v|
  count += 1 if ENV[v]
end
if count == 0
  puts "ERR: The following environment variables are required:"
  puts
  puts "             S3_REGION - the region your S3 bucket is in"
  puts "      S3_ACCESS_KEY_ID - the access key id required to access your S3 bucket"
  puts "  S3_SECRET_ACCESS_KEY - the secret access key required to access your S3 bucket"
  puts "        S3_BUCKET_NAME - the name of the S3 bucket"
  puts "             REPO_NAME - the name of the repository you were archiving"
  puts "            START_DATE - the earliest date you want to pull down files for. Use \"YYYY-MM-DD HH:MM:SS\" in 24h format."
  puts "              END_DATE - the latest date you want to pull down files for. Use \"YYYY-MM-DD HH:MM:SS\" in 24h format."
  puts
  exit
end

# If some of the required variables exist, but others don't – print out a list of
# all the missing variables.
required_vars.each do |v|
  if ENV[v].nil?
    errors << "ERR: No #{v.downcase.gsub("_", " ")} specified. Please specify one using #{v}."
  end
end

if ENV['S3_ENDPOINT'].nil? && ENV['S3_REGION'].nil?
  errors << "ERR: No s3 region specified. Please specify one using S3_REGION."
end

# Make sure the dates being passed in are in the correct format.
if ENV['START_DATE'] !~ /[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/
  errors << "ERR: START_DATE in wrong format. Please use \"YYYY-MM-DD HH:MM:SS\" in 24h format."
end

if ENV['END_DATE'] !~ /[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/
  errors << "ERR: END_DATE in wrong format. Please use \"YYYY-MM-DD HH:MM:SS\" in 24h format."
end

if errors.any?
  puts errors.join("\n")
  exit
end

# All S3 implementations need this
Aws.config.update({
  credentials: Aws::Credentials.new(ENV['S3_ACCESS_KEY_ID'], ENV['S3_SECRET_ACCESS_KEY'])
})

if ENV['DEBUG']
  logger = Logger.new($stdout)
  Aws.config.update({
    log_level: :debug,
    logger: logger,
    http_wire_trace: true
  })
end

if ENV['S3_REGION']
  Aws.config.update({
    region: ENV['S3_REGION']
  })
end

if ENV['S3_ENDPOINT']
  Aws.config.update({
    endpoint: ENV['S3_ENDPOINT']
  })
end

if ENV['S3_FORCE_PATH_STYLE']
  Aws.config.update({
    force_path_style: true
  })
end

bucket_name = ENV['S3_BUCKET_NAME']
repo_name   = ENV['REPO_NAME']
start_date  = Time.parse(ENV['START_DATE'])
end_date    = Time.parse(ENV['END_DATE'])

class S3FilenameParser
  attr_accessor :dataspace, :tags, :timestamp, :segment_id
  # filebeat/type/humio/error/true/humioBackfill/0/2020/03/06/20-09-02-j8zBEEtnyui4McNBwXyeTCG9.gz
  # humio/type/accesslog/error/true/host/go01/2019/09/17/00-18-48-YfZRpy3HqvpwqPYthINcO0AU.gz

  def initialize(object_key)
    s = object_key.split("/")
    @tags = {}
    @dataspace = s.shift
    while s.size > 4
      tag = s.shift(2)
      @tags[tag[0]] = tag[1]
    end
    year, month, day = s.shift(3)
    unless year =~ /[0-9]{4}/ && month =~ /[0-9]{2}/ && day =~ /[0-9]{2}/
      raise "date parsed incorrectly"
    end
    combined = s.shift
    cs = combined.split("-")
    time = cs.shift(3)
    @timestamp = Time.parse("#{year}-#{month}-#{day} #{time[0]}:#{time[1]}:#{time[2]}")
    @segment_id = cs.shift.split(".").first
  end

  def in_time_range?(start_date, end_date)
    @timestamp >= start_date && @timestamp <= end_date
  end

  def in_dataspace?(repo_name)
    @dataspace == repo_name
  end

  def tag_string
    @tags.collect{ |k,v| "#{k}-#{v}" }.join("_")
  end

  def filename
    "#{@dataspace}_#{tag_string}_#{@timestamp.to_i}_#{segment_id}"
  end

  def filename_with_ext(ext="gz")
    "#{filename}.#{ext}"
  end
end

s3 = Aws::S3::Resource.new
bucket = s3.bucket(bucket_name)

puts "BUCKET: #{bucket_name}"
puts "  REPO: #{repo_name}"
puts " START: #{start_date}"
puts "   END: #{end_date}"
puts

bucket.objects(prefix: "#{repo_name}/").each do |obj|
  begin
    s3file = S3FilenameParser.new(obj.key)

    if s3file.in_dataspace?(repo_name) && s3file.in_time_range?(start_date, end_date)

      puts "[#{s3file.timestamp}] FETCHING: #{obj.key} => #{obj.etag}"
      output = obj.get

      gz = Zlib::GzipReader.new(output.body)
      uncompressed_string = gz.read

      File.open("raw/#{s3file.filename_with_ext("raw")}", "w+") do |f|
        parser = NDJSON::Parser.new(StringIO.new(uncompressed_string.to_s))
        parser.each do |line|
          f << "#{line["@rawstring"]}\n"
        end
      end
    else
      if ENV['DEBUG']
        puts "[#{s3file.timestamp}]  SKIPPED: #{obj.key}"
      end
    end
  rescue => e
    if ENV['DEBUG']
      puts "FAILED: #{obj.key} ==> #{e.inspect}"
    end

    next
  end
end
