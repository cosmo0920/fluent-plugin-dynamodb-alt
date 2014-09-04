# fluent-plugin-dynamodb-alt

Alternative fluent plugin to output to DynamoDB.

[![Gem Version](https://badge.fury.io/rb/fluent-plugin-dynamodb-alt.png)](http://badge.fury.io/rb/fluent-plugin-dynamodb-alt)
[![Build Status](https://travis-ci.org/winebarrel/fluent-plugin-dynamodb-alt.svg)](https://travis-ci.org/winebarrel/fluent-plugin-dynamodb-alt)

## Installation

```sh
bundle install
bundle exec rake install
```

## Configuration

```
<match tag>
  type dynamodb_alt
  aws_key_id AKIAIOSFODNN7EXAMPLE
  aws_sec_key wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  region ap-northeast-1
  table_name my_table
  #concurrency 1

  # see http://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_PutItem.html#DDB-PutItem-request-Expected
  #expected id NULL,timestamp LT ${timestamp},key EQ "val"
  #conditional_operator OR

  #include_time_key true
  #include_tag_key true
</match>
```
