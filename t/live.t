#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Digest::SHA;
use File::Spec;
use File::Temp qw(tempfile);
use FindBin;

my $aws = File::Spec->catfile($FindBin::Bin, "..", "aws");
my $live = $ENV{AWS_TEST_LIVE};
plan skip_all => "set AWS_TEST_LIVE=1 to run tests against AWS" unless $live;

sub run_aws
{
    my(@argument) = @_;
    open(my $out, "-|", $^X, $aws, "--no-sanity-check", @argument) or die "run aws: $!";
    local($/);
    my $output = <$out>;
    close $out;
    ($? >> 8, defined($output) ? $output : "");
}

my($status, $identity) = run_aws("sts", "get-caller-identity");
is($status, 0, "signed STS GetCallerIdentity request succeeds");
like($identity, qr[<Arn>arn:aws(?:-[a-z]+)?:], "AWS returned the caller ARN");
like($identity, qr[<Account>\d{12}</Account>], "AWS returned the account number");

my $bucket = $ENV{AWS_TEST_BUCKET};

SKIP: {
    skip "set AWS_TEST_BUCKET to enable the S3 write/read/delete test", 6 unless $bucket;

    my $user = $ENV{USER} || "unknown";
    my $key = "timkay-aws-tests/$user-$$-" . time . ".txt";
    $key =~ s/[^A-Za-z0-9_.\/-]/-/g;
    my $payload = "timkay aws live test $$ " . time . "\n";
    my($source, $source_name) = tempfile();
    print $source $payload;
    close $source;
    my($target, $target_name) = tempfile();
    close $target;

    my $cleanup_needed;
    ($status) = run_aws("s3", "put", "$bucket/$key", $source_name);
    is($status, 0, "uploaded a test object to S3");
    $cleanup_needed = !$status;

    ($status) = run_aws("s3", "get", "$bucket/$key", $target_name);
    is($status, 0, "downloaded the test object from S3");
    my $downloaded = "";
    if (open(my $in, "<", $target_name))
    {
        local($/);
        $downloaded = <$in>;
        close $in;
    }
    is($downloaded, $payload, "downloaded bytes match uploaded bytes");

    ($status) = run_aws("s3", "delete", "$bucket/$key");
    is($status, 0, "deleted the test object from S3");
    $cleanup_needed = 0 unless $status;

    ($status) = run_aws("s3", "head", "$bucket/$key");
    isnt($status, 0, "deleted object is no longer present");
    ok(!$cleanup_needed, "live test left no object behind");

    run_aws("s3", "delete", "$bucket/$key") if $cleanup_needed;
}

SKIP: {
    skip "set AWS_TEST_BUCKET to enable the S3 multipart test", 6 unless $bucket;

    my $user = $ENV{USER} || "unknown";
    my $key = "timkay-aws-tests/$user-$$-" . time . "-multipart.bin";
    $key =~ s/[^A-Za-z0-9_.\/-]/-/g;
    my($source, $source_name) = tempfile();
    binmode $source;
    print $source "timkay aws multipart test\n";
    print $source "\0" x (1024 * 1024) for 1..12;
    close $source;
    my($target, $target_name) = tempfile();
    close $target;

    my $cleanup_needed;
    ($status) = run_aws("--md5", "--parts=3", "s3", "put", "$bucket/$key", $source_name);
    is($status, 0, "uploaded a checksummed three-part test object to S3");
    $cleanup_needed = !$status;

    my($head_status, $head) = run_aws("s3", "head", "$bucket/$key");
    like($head, qr/^ETag: \"[0-9a-f]{32}-3\"\r?$/mi, "S3 confirms a three-part multipart upload");
    like($head, qr/^Content-Length: 12582938\r?$/mi, "multipart object has the expected length");

    ($status) = run_aws("s3", "get", "$bucket/$key", $target_name);
    is($status, 0, "downloaded the multipart test object");
    my $source_hash = Digest::SHA->new(256)->addfile($source_name)->hexdigest;
    my $target_hash = Digest::SHA->new(256)->addfile($target_name)->hexdigest;
    is($target_hash, $source_hash, "multipart download matches the source SHA-256");

    ($status) = run_aws("s3", "delete", "$bucket/$key");
    is($status, 0, "deleted the multipart test object");
    $cleanup_needed = 0 unless $status;
    run_aws("s3", "delete", "$bucket/$key") if $cleanup_needed;
}

done_testing();
