# After 11 years, Tim Kay's `./aws` is back!

The original code still works with only minor updates.

Updates: native `./aws login`, with no AWS CLI or SDK required.

# aws: a small AWS command line

`aws` is a single-file Perl command-line program for Amazon Web Services. It
was first released in 2007—when there were no AWS command-line tools!

The design is deliberately austere: download one file, make it executable,
and use it. Other than Perl and its core modules, the only runtime dependency
is `curl`.

## A little history

This was one of the earliest unified command-line tools for AWS, initially
covering EC2 and S3 and later growing to cover SQS, SDB, ELB, IAM, Elastic
Beanstalk, RDS, STS, Route 53, CloudFormation, and Product Advertising.

It became super popular in the early AWS community:

- An [archived AWS Developer Community listing from February
  2009](https://web.archive.org/web/20090202030321/http://developer.amazonwebservices.com/connect/entry.jspa?externalID=739&categoryID=85)
  calls it the "top-rated community code for all of EC2 and S3." At that
  point the listing had 17 reviews, all five-star.
- On an [archived September 2008 S3 code listing sorted by best
  rating](https://web.archive.org/web/20080903005109/http://developer.amazonwebservices.com/connect/kbcategory.jspa?categoryID=47&resultOffset=0&sortField=107&sortOrder=0&filterEntryTypeID=-1),
  `aws` appears first.
- By the [August 2010 AWS archive
  snapshot](https://web.archive.org/web/20100827083915/http://developer.amazonwebservices.com/connect/entry.jspa?categoryID=85&externalID=739),
  it had 22 reviews: 21 five-star reviews and one four-star review. The
  displayed average was still five stars.

The lone four-star review was posted on August 11, 2009, after 19 five-star
reviews. Its reviewer wrote, "I'm reserving a star for the very best of all
tools," while describing the review as favorable. Amazon's rating algorithm
briefly allowed a project with a single five-star review to outrank `aws`. I
contacted Amazon about the ranking method; it was subsequently revised, and
`aws` returned to the top.

Contemporary recommendations and production use provide another measure of
its reach:

- [Simon Willison called it the best command-line client he had found for EC2
  and S3](https://simonwillison.net/2009/May/19/aws/) in May 2009.
- [AWS users reported preferring it to Amazon's original Java
  tools](https://stackoverflow.com/questions/733013/alternative-tools-for-amazon-ec2)
  in 2009.
- [Linux Magazine called it a perfect tool for scripted S3
  backups](https://www.linux-magazine.com/Online/Blogs/Productivity-Sauce-Dmitri-s-open-source-blend-of-productive-computing/Perfect-Backup-Solution-with-Amazon-S3-and-aws)
  in 2010.
- It appeared in [QCon's 2010 survey of AWS
  tools](https://qconlondon.com/london-2010/qconlondon.com/dl/qcon-london-2010/slides/ChrisRichardson_DeployingJavaApplicationsOnAmazonEC2.pdf)
  as an alternative to Amazon's command-line tools.
- Researchers chose it for a [VMD integration with
  EC2](https://www.researchgate.net/publication/273594841_The_Design_and_Implementation_of_the_VMD_Plugin_for_NAMD_Simulations_on_the_Amazon_Cloud)
  because it was simple to install and use and required only Perl and `curl`.
- [Transloadit used it for five years and nearly a petabyte of S3
  exports](https://transloadit.com/blog/2015/02/s3-changes/) before moving to
  Amazon's official CLI.

The project was maintained by one person while AWS added services and changed
APIs at a remarkable pace. Amazon was never willing to assist with maintaining
it, and eventually keeping up stopped being sustainable.

One feature illustrates both the care that went into the tool and the scale it
reached. Authentication failures were commonly caused by a bad local clock or
broken SSL configuration. As a sanity check, `aws` retrieved
`s3://connection/test`. The response headers supplied the server time and
enough information to diagnose SSL problems; `aws` used the time difference
to correct clock skew when signing subsequent requests. After this check was
introduced, support requests plummeted.

The check happened every time `./aws` was invoked unless the user turned it
off. Requests to the bucket eventually cost $400 per month on my personal AWS
bill. It then took four months to persuade Amazon to transfer the bucket into
its internal ownership after Amazon claimed that such a transfer was not
technically possible.

The code remains useful and is also a small piece of early cloud-computing
history.

## Install

Download the program and make it executable:

```sh
curl -L https://raw.githubusercontent.com/timkay/aws/master/aws -o aws
chmod +x aws
```

Version 2.0 reads the same `~/.aws/credentials` and `~/.aws/config` files as
the official AWS CLI. `AWS_PROFILE` or `--profile` selects a named profile.
The standard `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`, `AWS_REGION`, and `AWS_DEFAULT_REGION` environment
variables are supported.

The original `~/.awssecret`, `EC2_ACCESS_KEY`, and `EC2_SECRET_KEY` forms
remain supported for existing scripts.

For more documentation, see [timkay.com/aws](https://timkay.com/aws/) and the
[GitHub wiki](https://github.com/timkay/aws/wiki).

## Version 2.0

Version 2.0 modernizes authentication while preserving the qualities that
made `aws` useful:

- one readable Perl file;
- no non-core Perl dependencies;
- `curl` as the HTTP transport;
- small, direct commands and useful text output;
- support limited to the services already represented in this program.

Signature Version 4 is now the default. Version 2.0 supports:

- the standard `~/.aws/credentials` and `~/.aws/config` files;
- `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_SESSION_TOKEN`, `AWS_REGION`, and `AWS_DEFAULT_REGION`;
- `credential_process`, web-identity roles, IMDSv2 instance-role credentials,
  and ECS container credentials without making any of them dependencies;
- native `aws login` console authentication, including automatic refresh;
- AWS CLI-style service prefixes where they are unambiguous, so both
  `aws describe-instances` and `aws ec2 describe-instances` work.

Web identity uses the standard `AWS_ROLE_ARN`,
`AWS_WEB_IDENTITY_TOKEN_FILE`, and optional `AWS_ROLE_SESSION_NAME`
variables (or the corresponding profile settings).

### Command help and common options

Run a command with `--help` to see its positional arguments, command-specific
switches, and the most useful common options:

```sh
./aws s3 put --help
./aws ec2 run-instances --help
```

Common options include `--profile`, `--region`, `--request`, `--retry`, and
`--max-time`. S3 commands also document `--content-type`, `--md5`, `--parts`,
`--progress`, `--public`, `--private`, and `--requester`. These options are
meta-parameters: they may be placed before or after the command name and
modify how the request is prepared or transported rather than becoming AWS
API parameters.

By default, `aws` passes `--retry 3` to the installed `curl`. Retry decisions
therefore follow that curl version. Current curl retries timeouts and HTTP
408, 429, 500, 502, 503, 504, 522, and 524 responses with backoff; ordinary
client errors such as 404 are not retried. `--max-time` limits each individual
attempt, not the combined retry period. Multipart upload additionally retries
a part when no HTTP response was received. A checksum mismatch is reported
but is not automatically retried.

S3 subresources remain deliberately direct. For example, configure a static
website by putting AWS's XML configuration document, and list or recover
object versions with the standard S3 query parameters:

```sh
./aws s3 put 'my-bucket?website' website.xml
./aws s3 get 'my-bucket?versions'
./aws s3 get 'my-bucket/path/file?versionId=VERSION' previous-file
./aws s3 put my-bucket/path/file previous-file
```

### Login with console credentials

`aws` can obtain short-lived credentials from an existing AWS Management
Console login without installing Amazon's CLI or creating a long-lived access
key:

```sh
./aws login
```

Use `--profile NAME` for a named profile and `--region REGION` to select the
AWS Sign-In endpoint:

```sh
./aws login --profile development --region us-west-2
```

The command prints an AWS URL. Open it in any browser, approve local
development access, and paste the entire displayed response (the long Base64
string) at the prompt. `aws` decodes it and verifies that it belongs to the
current login request. This cross-device flow also works over SSH, so
`--remote` is accepted for compatibility but is not required.

The implementation performs PKCE and DPoP signing within the Perl file, calls
AWS Sign-In directly with `curl`, records `login_session` in the selected
profile, and stores its refresh material under `~/.aws/timkay-login`. Cache
files and the config file are written with user-only permissions. Set
`AWS_LOGIN_CACHE_DIRECTORY` to use another cache location.

The AWS identity must be allowed to use local-development sign-in. If AWS
reports insufficient permissions, attach or otherwise grant the
`SignInLocalDevelopmentAccess` policy. Login credentials last about 15 minutes
at a time and are refreshed automatically for the lifetime of the console
session; run `./aws login` again after that session expires.

Use `--signature-v2` only when talking to a legacy AWS-compatible endpoint
that still requires the old protocol.

Full command-line and output compatibility with the official CLI is not a
goal. Its generated command surface, service models, pagination behavior, and
multiple output formats would sacrifice the small implementation and create
an open-ended maintenance commitment.

## Tests

The test suite uses only Perl core modules and `curl`:

```sh
prove -v t/*.t
```

The normal suite includes deterministic offline tests and a harmless request
to AWS's public `connection/test` object. Set `NO_NETWORK_TESTING=1` to skip
that smoke test.

The live authentication test calls STS `GetCallerIdentity`. If
`AWS_TEST_BUCKET` is also set to a dedicated test bucket, it uploads,
downloads, verifies, and deletes both a small object and a three-part 12 MiB
multipart object:

```sh
AWS_TEST_LIVE=1 AWS_TEST_BUCKET=my-test-bucket prove -v t/live.t
```

The selected profile or environment must provide credentials with STS access
and, for the write test, `s3:PutObject`, `s3:GetObject`, and `s3:DeleteObject`
on that bucket. Set `AWS_REGION` to the bucket's region when it is not already
in the selected profile. The test makes a best-effort delete if an intermediate
assertion fails.
