require "json"
require "logger"

@logger = Logger.new(STDOUT)
@logger.progname = 'ec2_tag_facts'

# Return a normalized name for the fact.
# Replace any non-word character with "_"
def normalize_tag_name(name)
  normalized_name = name.downcase.gsub(/\W+/, "_")
  "ec2_tag_#{normalized_name}"
end

# Executes AWS API call and allow us to catch any errors
# and retry if necessary
def exec_aws_api_call(instance_id, region)
  retries   = 0
  tags      = nil
  query_cmd = "aws ec2 describe-tags --filters \"Name=resource-id,Values=#{instance_id}\" --region #{region} --output json"

  begin
    @logger.info("query AWS API ##{retries}")
    tags = Facter::Core::Execution.execute(query_cmd, :timeout => 10)
    @logger.info("query result for ##{retries}: #{tags}")

    # Workaround to raise an error if the command output is empty
    # This may happen if the credentials are wrong:
    # "...An error occurred (AuthFailure) when calling the..." (exit code: 255)
    if tags.empty?
      raise Facter::Core::Execution::ExecutionFailure, "Empty result from command aws"
    end
  rescue Facter::Core::Execution::ExecutionFailure => e
    @logger.error("error querying AWS API: #{e.message}")
    retry if (retries += 1) <= 3
    raise e
  end

  tags
end

# The cache is enabled through Puppet using Hiera:
# ```
# ec2tagfacts::cache_aws_api_calls: true
# ```
#
# The `ec2tagfacts` class will create the `cache_enabled` file that
# is being used here to identify if the API calls should be cached.
#
# With this logic we need at least 2 calls to the AWS API:
# 1. When Puppet runs for the first time will create the `cache_enabled` file
# 2. This fact now knows that the calls should be cached
def query_aws_api(instance_id, region)
  # If you change the destination of this file you should do the same
  # in the Puppet class.
  cache_enabled = '/var/tmp/ec2tagfacts.cache_enabled'
  cache_content = '/var/tmp/ec2tagfacts.cache_content'
  tags          = {}

  if File.exist?(cache_enabled)
    @logger.info('cache is enabled')
    if File.exist?(cache_content)
      @logger.info('reading cache from file')
      tags = File.read(cache_content)
    else
      tags = exec_aws_api_call(instance_id, region)
      File.open(cache_content, 'w') { |f| f.write(tags) }
    end
  else
    tags = exec_aws_api_call(instance_id, region)
  end

  JSON.parse(tags)
end

ec2_metadata      = Facter.value(:ec2_metadata)
instance_id       = ec2_metadata.fetch('instance-id')
availability_zone = ec2_metadata.fetch('placement').fetch('availability-zone')
region            = availability_zone[0..-2]

tags = query_aws_api(instance_id, region)

tags['Tags'].each do |tag|
  name  = normalize_tag_name(tag['Key'])
  value = tag['Value']

  Facter.add(name) do
    setcode { value }
  end
end
