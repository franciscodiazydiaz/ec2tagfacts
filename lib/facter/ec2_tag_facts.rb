require "json"

# Return a normalized name for the fact.
# Replace any non-word character with "_"
def normalize_tag_name(name)
  normalized_name = name.downcase.gsub(/\W+/, "_")
  "ec2_tag_#{normalized_name}"
end

# The cache is enabled through Puppet using Hiera:
# ```
# ec2tagfacts::cache_aws_api_calls: true
# ```
#
# The `ec2tagfacts` class will create the `cache_enabled` file that
# is being used here to identify if the API calls should be cached.
def query_aws_api(instance_id, region)
  # If you change the destination of this file you should do the same
  # in the Puppet class.
  cache_enabled = '/var/tmp/ec2tagfacts.cache_enabled'
  cache_content = '/var/tmp/ec2tagfacts.cache_content'
  tags          = {}

  query_cmd = "awss ec2 describe-tags --filters \"Name=resource-id,Values=#{instance_id}\" --region #{region} --output json"

  if File.exist?(cache_enabled)
    if File.exist?(cache_content)
      tags = File.read(cache_content)
    else
      tags = Facter::Core::Execution.execute(query_cmd)
      File.open(cache_content, 'w') { |f| f.write(tags) }
    end
  else
    tags = Facter::Core::Execution.execute(query_cmd)
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

