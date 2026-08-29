#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

plan skip_all => "network tests disabled by NO_NETWORK_TESTING"
    if $ENV{NO_NETWORK_TESTING};

open(my $out, "-|", "curl", "-q", "-sS", "--max-time", "10", "--include",
     "https://connection.s3.amazonaws.com/test")
    or plan skip_all => "curl is unavailable";
local($/);
my $response = <$out>;
close $out;
my $status = $? >> 8;

is($status, 0, "reached the live AWS S3 connection-test object");
like($response, qr[^HTTP/\S+ 200 OK]m, "AWS returned HTTP 200");
like($response, qr[^Date: .+ GMT\r?$]mi, "AWS returned server time for clock-skew correction");
like($response, qr[Your connection test succeeded], "AWS returned the expected connection-test body");

done_testing();
