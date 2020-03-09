# Humio S3 Archive Tools

This repository contains scripts to help with interact with data Humio
has stored in S3 via the [S3 Archive](https://docs.humio.com/cluster-management/storage-and-backup/s3-archiving/)
feature. Currently, it just contains a single script designed to fetch
the gzipped NDJSON archive files from S3 and convert them into raw log
files that can be re-ingested using a tool like [Filebeat](https://docs.humio.com/integrations/data-shippers/beats/filebeat/).

## Pre-requisites

### Install Ruby
These scripts are written in Ruby. As such, you should have Ruby installed
on the system you're running these scripts from. You can get more information
on installing Ruby at the [official Ruby website](https://www.ruby-lang.org/en/documentation/installation/).

### Install Bundler
Once you have Ruby installed, install the `bundler` gem:

```
gem install bundler
```

### Install Git
You'll want to install git to clone this repository. There are a variety of
methods to install git (e.g., Homebrew if you're on a Mac), but this is a
good place to start:

https://git-scm.com/downloads

## Clone the Repo
Once you have all the pre-requisites taken care of, you need to clone the
repository so you have a copy on your local system. To do that, run this:

```
git clone https://github.com/humio/humio-s3-archive-tools.git
```

You should now have a directory titled `humio-s3-archive-tools`. Go ahead
and switch to that directory.

## Install Required Rubygems
Now we need to install the Rubygems the scripts require. To do that, run:

```
bundle install
```

## Provide Required Configuration
The scripts rely on a variety of environment variables to function. You
can set these easily by creating a `.env` file in the directory and pasting
the following into it (changing the example values according to your what's
needed for your own environment):

```
# the AWS region the S3 bucket you configured Humio to use for S3 Archives
AWS_REGION="us-east-1"

# an AWS Access Key ID that has read/list privileges
AWS_ACCESS_KEY_ID="..."
# the corresponding AWS Secret Access Key
AWS_SECRET_ACCESS_KEY="..."

# the name of the S3 bucket you've configured the repository to archive to
BUCKET_NAME="my-repo-archive"

# the name of the Humio repository you're wanting to interact with archives for
REPO_NAME="humio"

# the earliest timestamp you want to interact with. note that this is in terms
# of the timestamp Humio has set on the S3 Archive files.
START_DATE="2019-10-05 00:00:00"

# the latest timestamp you want to interact with. note that this is in terms
# of the timestamp Humio has set on the S3 Archive files.
END_DATE="2019-10-06 00:00:00"
```

## Run the Script
Now that everything is ready to go, you can execute the script by running:

```
bundle exec ruby fetch.rb
```

Depending upon the timerange you've specified in `START_DATE` and `END_DATE`
combined with how much data you've ingested on your repository, this may
take quite a while to run. It currently has to scan ALL files uploaded for
the repository to S3 regardless of the time you specify even though it will
only fetch the ones that match your timeframe (this is due to how Humio
currently names the files it uploads).

Once the process is complete, you'll have a series of files stored in the
`raw/` directory with a `.raw` suffix. These files will contain the raw
logs extracted from the NDJSON files uploaded to S3. The filenames follow
the format:

```
$REPO_$TAGNAME1-$TAGVALUE1_$TAGNAME2-$TAGVALUE2_..._$UNIXTIMESTAMP_$SEGMENTID.raw
```

The `$UNIXTIMESTAMP` is the time of the first even in the file.

## Troubleshooting
There is a modicum of error handling in the script, but if you do run into
an exception please report it to support@humio.com.

If you'd like more verbose output while this is running add the following
to your `.env` file:

```
DEBUG="1"
```

This will show files that are being skipped or that failed to parse properly.