#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use IO::File;
use IPC::Open2;
use MIME::Base64 qw(encode_base64);
use FindBin;

my $aws = File::Spec->catfile($FindBin::Bin, "..", "aws");

sub write_file
{
    my($path, $content) = @_;
    my $out = IO::File->new($path, ">") or die "$path: $!";
    print $out $content;
    close $out;
}

sub load_file
{
    my($path) = @_;
    my $in = IO::File->new($path, "<") or die "$path: $!";
    local($/);
    my $content = <$in>;
    close $in;
    $content;
}

sub run_aws
{
    my($environment, @argument) = @_;
    local %ENV = %ENV;
    delete @ENV{qw(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
                   EC2_ACCESS_KEY EC2_SECRET_KEY AWS_PROFILE AWS_DEFAULT_PROFILE
                   AWS_REGION AWS_DEFAULT_REGION AWS_CONFIG_FILE
                   AWS_SHARED_CREDENTIALS_FILE AWS_CONTAINER_CREDENTIALS_FULL_URI
                   AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_ROLE_ARN
                   AWS_ROLE_SESSION_NAME AWS_WEB_IDENTITY_TOKEN_FILE
                   AWS_LOGIN_CACHE_DIRECTORY TIMKAY_AWS_TESTING
                   TIMKAY_AWS_LOGIN_STATE)};
    @ENV{keys %$environment} = values %$environment;
    $ENV{AWS_EC2_METADATA_DISABLED} = "true" unless exists $environment->{AWS_EC2_METADATA_DISABLED};

    open(my $out, "-|", $^X, $aws, @argument) or die "run aws: $!";
    local($/);
    my $output = <$out>;
    close $out;
    my $status = $? >> 8;
    ($status, defined($output) ? $output : "");
}

sub run_aws_input
{
    my($environment, $input, @argument) = @_;
    local %ENV = %ENV;
    delete @ENV{qw(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
                   EC2_ACCESS_KEY EC2_SECRET_KEY AWS_PROFILE AWS_DEFAULT_PROFILE
                   AWS_REGION AWS_DEFAULT_REGION AWS_CONFIG_FILE
                   AWS_SHARED_CREDENTIALS_FILE AWS_CONTAINER_CREDENTIALS_FULL_URI
                   AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_ROLE_ARN
                   AWS_ROLE_SESSION_NAME AWS_WEB_IDENTITY_TOKEN_FILE
                   AWS_LOGIN_CACHE_DIRECTORY TIMKAY_AWS_TESTING
                   TIMKAY_AWS_LOGIN_STATE)};
    @ENV{keys %$environment} = values %$environment;
    $ENV{AWS_EC2_METADATA_DISABLED} = "true" unless exists $environment->{AWS_EC2_METADATA_DISABLED};

    my($out, $in);
    my $pid = IPC::Open2::open2($out, $in, $^X, $aws, @argument);
    print $in $input;
    close $in;
    local($/);
    my $output = <$out>;
    close $out;
    waitpid($pid, 0);
    ($? >> 8, defined($output) ? $output : "");
}

my($status, $output) = run_aws({}, "--version");
is($status, 0, "--version succeeds");
is($output, "aws 2.0\n", "major version is 2.0");

my $dir = tempdir(CLEANUP => 1);
my $credentials = File::Spec->catfile($dir, "credentials");
my $config = File::Spec->catfile($dir, "config");
write_file($credentials, <<'CREDS');
[default]
aws_access_key_id = DEFAULTKEY
aws_secret_access_key = default-secret

[work]
aws_access_key_id = PROFILEKEY
aws_secret_access_key = profile-secret
aws_session_token = profile-token
CREDS
write_file($config, <<'CONFIG');
[default]
region = us-east-1

[profile work]
region = us-west-2
CONFIG

my %profile_env = (
    AWS_SHARED_CREDENTIALS_FILE => $credentials,
    AWS_CONFIG_FILE => $config,
    AWS_PROFILE => "work",
);
($status, $output) = run_aws(\%profile_env,
    "--no-sanity-check", "--request", "ec2", "describe-instances");
is($status, 0, "profile request succeeds");
like($output, qr[^https://ec2\.us-west-2\.amazonaws\.com/], "region comes from shared config");
like($output, qr[X-Amz-Credential=PROFILEKEY%2F], "credentials come from selected profile");
like($output, qr[X-Amz-Security-Token=profile-token], "profile session token is signed");

my %environment_precedence = (%profile_env,
    AWS_ACCESS_KEY_ID => "ENVKEY",
    AWS_SECRET_ACCESS_KEY => "env-secret",
    AWS_SESSION_TOKEN => "env-token",
    AWS_REGION => "eu-west-1",
);
($status, $output) = run_aws(\%environment_precedence,
    "--no-sanity-check", "--request", "describe-instances");
is($status, 0, "environment credential request succeeds");
like($output, qr[^https://ec2\.eu-west-1\.amazonaws\.com/], "AWS_REGION overrides profile region");
like($output, qr[X-Amz-Credential=ENVKEY%2F], "environment credentials override profile");
like($output, qr[X-Amz-Security-Token=env-token], "environment session token is signed");

my $helper = File::Spec->catfile($dir, "credential-process.pl");
write_file($helper, <<'HELPER');
print <<'JSON';
{"Version":1,"AccessKeyId":"PROCESSKEY","SecretAccessKey":"process-secret","SessionToken":"process-token"}
JSON
HELPER
write_file($config, "[profile process]\nregion = ap-southeast-2\ncredential_process = $^X $helper\n");
my %process_env = (
    AWS_SHARED_CREDENTIALS_FILE => File::Spec->catfile($dir, "missing"),
    AWS_CONFIG_FILE => $config,
    AWS_PROFILE => "process",
);
($status, $output) = run_aws(\%process_env,
    "--no-sanity-check", "--request", "sts", "get-caller-identity");
is($status, 0, "credential_process request succeeds");
like($output, qr[X-Amz-Credential=PROCESSKEY%2F], "credential_process supplies credentials");
like($output, qr[X-Amz-Security-Token=process-token], "credential_process session token is signed");

my $login_curl = File::Spec->catfile($dir, "login-curl");
write_file($login_curl, <<'LOGIN_CURL');
#!/usr/bin/perl
my($body, $dpop);
for (my $i = 0; $i < @ARGV; $i++) {
    $dpop = $ARGV[$i + 1] if $ARGV[$i] eq "-H" && ($ARGV[$i + 1] || "") =~ /^DPoP: /;
    if ($ARGV[$i] eq "--data-binary" && ($ARGV[$i + 1] || "") =~ /^\@(.*)/) {
        open(my $in, "<", $1) or die $!;
        local($/);
        $body = <$in>;
        close $in;
    }
}
open(my $capture, ">>", $ENV{LOGIN_CAPTURE}) or die $!;
print $capture "BODY=$body\nDPOP=$dpop\n";
close $capture;
my $refresh = $body =~ /refresh_token/;
my $key = $refresh ? "LOGINREFRESHKEY" : "LOGINKEY";
print '{"accessToken":{"accessKeyId":"' . $key .
      '","secretAccessKey":"login-secret","sessionToken":"login-token"},' .
      '"tokenType":"aws_sigv4","expiresIn":900,"refreshToken":"login-refresh",' .
      '"idToken":"x.eyJzdWIiOiJhcm46YXdzOmlhbTo6MTIzNDU2Nzg5MDEyOnVzZXIvVGVzdFVzZXIifQ.x"}' . "\n200";
LOGIN_CURL
chmod 0700, $login_curl;
my $login_config = File::Spec->catfile($dir, "login-config");
my $login_cache = File::Spec->catdir($dir, "login-cache");
my $login_capture = File::Spec->catfile($dir, "login-capture");
my %login_env = (
    AWS_CONFIG_FILE => $login_config,
    AWS_SHARED_CREDENTIALS_FILE => File::Spec->catfile($dir, "missing-login-credentials"),
    AWS_LOGIN_CACHE_DIRECTORY => $login_cache,
    LOGIN_CAPTURE => $login_capture,
    TIMKAY_AWS_TESTING => 1,
    TIMKAY_AWS_LOGIN_STATE => "test-state",
);
my $browser_answer = encode_base64("code=test-authorization-code&state=test-state", "");
($status, $output) = run_aws_input(\%login_env, "$browser_answer\n",
    "--curl=$login_curl", "--region=us-west-2", "--profile=console", "login");
is($status, 0, "native login succeeds without the AWS CLI");
like($output, qr[Open this URL in a browser:], "login prints its austere cross-device instructions");
like($output, qr[client_id=arn%3Aaws%3Asignin%3A%3A%3Adevtools%2Fcross-device], "login uses the AWS cross-device client");
like($output, qr[Logged in profile console as arn:aws:iam::123456789012:user/TestUser], "login reports the selected identity");
my $saved_config = load_file($login_config);
like($saved_config, qr/^\[profile console\]$/m, "login creates the selected profile");
like($saved_config, qr/^login_session = arn:aws:iam::123456789012:user\/TestUser$/m, "login records its session in the profile");
like($saved_config, qr/^region = us-west-2$/m, "login records the region");
is(sprintf("%04o", (stat($login_config))[2] & 0777), "0600", "login protects the profile config");
my $captured_login = load_file($login_capture);
like($captured_login, qr/"grantType":"authorization_code"/, "login exchanges an authorization code itself");
like($captured_login, qr/"code":"test-authorization-code"/, "login sends the entered authorization code");
like($captured_login, qr/^DPOP=DPoP: [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/m, "login signs its own DPoP proof");

($status, $output) = run_aws(\%login_env,
    "--no-sanity-check", "--request", "--profile=console", "sts", "get-caller-identity");
is($status, 0, "login profile request succeeds");
like($output, qr[X-Amz-Credential=LOGINKEY%2F], "login cache supplies temporary credentials");
like($output, qr[X-Amz-Security-Token=login-token], "login cache supplies its session token");

my($cache_file) = glob(File::Spec->catfile($login_cache, "*.json"));
is(sprintf("%04o", (stat($cache_file))[2] & 0777), "0600", "login protects its credential cache");
my $expired_cache = load_file($cache_file);
$expired_cache =~ s/"ExpiresAt":\d+/"ExpiresAt":0/;
write_file($cache_file, $expired_cache);
($status, $output) = run_aws(\%login_env,
    "--curl=$login_curl", "--no-sanity-check", "--request", "--profile=console", "sts", "get-caller-identity");
is($status, 0, "expired login session refresh succeeds");
like($output, qr[X-Amz-Credential=LOGINREFRESHKEY%2F], "refresh supplies new temporary credentials");
like(load_file($login_capture), qr/"grantType":"refresh_token"/, "refresh is performed directly by the Perl tool");

($status, $output) = run_aws({
        AWS_ACCESS_KEY_ID => "EC2KEY",
        AWS_SECRET_ACCESS_KEY => "ec2-secret",
        AWS_REGION => "us-east-1",
    }, "--no-sanity-check", "--request", "ec2", "run-instances", "ami-test",
       "--instance-type", "t3.nano", "--dry-run", "true",
       "--http-endpoint", "enabled", "--http-tokens", "required",
       "--http-put-response-hop-limit", "1");
is($status, 0, "modern EC2 launch request succeeds offline");
like($output, qr/Version=2016-11-15/, "EC2 uses the current stable API version");
like($output, qr/DryRun=true/, "EC2 launch supports DryRun");
like($output, qr/MetadataOptions\.HttpEndpoint=enabled/, "EC2 launch explicitly enables metadata");
like($output, qr/MetadataOptions\.HttpTokens=required/, "EC2 launch requires IMDSv2");
like($output, qr/MetadataOptions\.HttpPutResponseHopLimit=1/, "EC2 launch limits metadata hops");

my $metadata = File::Spec->catfile($dir, "metadata-curl.pl");
write_file($metadata, <<'METADATA');
my $url = $ARGV[-1] || "";
if ($url =~ m{/latest/api/token$}) {
    print "imdsv2-token";
} elsif ($url =~ m{/security-credentials/$}) {
    print "TestRole\n";
} elsif ($url =~ m{/security-credentials/TestRole$}) {
    print '{"AccessKeyId":"IMDSKEY","SecretAccessKey":"imds-secret","Token":"imds-token"}';
} elsif ($url =~ m{/container-credentials$}) {
    print '{"AccessKeyId":"CONTAINERKEY","SecretAccessKey":"container-secret","Token":"container-token"}';
} elsif ($url =~ m{^https://sts\.[^/]+/|^https://sts\.amazonaws\.com/}) {
    print '<Credentials><AccessKeyId>WEBKEY</AccessKeyId><SecretAccessKey>web-secret</SecretAccessKey><SessionToken>web-token</SessionToken></Credentials>';
} else {
    exit 22;
}
METADATA

my %imds_env = (
    AWS_CONFIG_FILE => File::Spec->catfile($dir, "missing-config"),
    AWS_SHARED_CREDENTIALS_FILE => File::Spec->catfile($dir, "missing-credentials"),
    AWS_EC2_METADATA_DISABLED => "false",
);
my $metadata_wrapper = File::Spec->catfile($dir, "metadata-curl");
write_file($metadata_wrapper, "#!/bin/sh\nexec '$^X' '$metadata' \"\$@\"\n");
chmod 0700, $metadata_wrapper;
($status, $output) = run_aws(\%imds_env,
    "--curl=$metadata_wrapper", "--no-sanity-check", "--request", "sts", "get-caller-identity");
is($status, 0, "IMDSv2 credential request succeeds");
like($output, qr[X-Amz-Credential=IMDSKEY%2F], "IMDSv2 supplies credentials");
like($output, qr[X-Amz-Security-Token=imds-token], "IMDSv2 session token is signed");

my %container_env = (%imds_env,
    AWS_CONTAINER_CREDENTIALS_FULL_URI => "http://127.0.0.1/container-credentials",
);
($status, $output) = run_aws(\%container_env,
    "--curl=$metadata_wrapper", "--no-sanity-check", "--request", "sts", "get-caller-identity");
is($status, 0, "container credential request succeeds");
like($output, qr[X-Amz-Credential=CONTAINERKEY%2F], "container endpoint supplies credentials");
like($output, qr[X-Amz-Security-Token=container-token], "container session token is signed");

my $web_token = File::Spec->catfile($dir, "web-identity-token");
write_file($web_token, "header.payload.signature\n");
my %web_env = (%imds_env,
    AWS_ROLE_ARN => "arn:aws:iam::123456789012:role/TestRole",
    AWS_WEB_IDENTITY_TOKEN_FILE => $web_token,
    AWS_REGION => "us-west-2",
);
($status, $output) = run_aws(\%web_env,
    "--curl=$metadata_wrapper", "--no-sanity-check", "--request", "sts", "get-caller-identity");
is($status, 0, "web identity credential request succeeds");
like($output, qr[X-Amz-Credential=WEBKEY%2F], "web identity supplies credentials");
like($output, qr[X-Amz-Security-Token=web-token], "web identity session token is signed");

for my $case (
    ["elb", "describe-lbs", "elasticloadbalancing"],
    ["ebn", "describe-applications", "elasticbeanstalk"],
) {
    my($service, $operation, $signing_name) = @$case;
    ($status, $output) = run_aws({
            AWS_ACCESS_KEY_ID => "SERVICEKEY",
            AWS_SECRET_ACCESS_KEY => "service-secret",
            AWS_REGION => "us-east-1",
        }, "--no-sanity-check", "--request", $service, $operation);
    is($status, 0, "$service SigV4 request succeeds");
    like($output, qr[%2F$signing_name%2Faws4_request], "$service uses its AWS signing service name");
}

my $s3_curl = File::Spec->catfile($dir, "s3-curl");
write_file($s3_curl, <<'S3CURL');
#!/usr/bin/perl
if (grep {$_ eq "--dump-header"} @ARGV) {
    print "HTTP/1.1 200 OK\r\nETag: \"d41d8cd98f00b204e9800998ecf8427e\"\r\n\r\n";
}
S3CURL
chmod 0700, $s3_curl;
my($empty_file, $empty_name) = File::Temp::tempfile(DIR => $dir);
close $empty_file;
($status, $output) = run_aws({
        AWS_ACCESS_KEY_ID => "S3KEY",
        AWS_SECRET_ACCESS_KEY => "s3-secret",
        AWS_REGION => "us-east-1",
    }, "--curl=$s3_curl", "--no-sanity-check", "s3", "put", "test-bucket/test-key", $empty_name);
is($status, 0, "S3 PUT accepts a successful empty response body");

my %vector_env = (
    AWS_ACCESS_KEY_ID => "AKIAIOSFODNN7EXAMPLE",
    AWS_SECRET_ACCESS_KEY => "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    TIMKAY_AWS_TESTING => 1,
    TIMKAY_AWS_SIGNING_TIME => "20130524T000000Z",
);
($status, $output) = run_aws(\%vector_env,
    "--no-sanity-check", "--request", "--expire-time=86400", "--region=us-east-1",
    "s3", "get", "examplebucket/test.txt");
is($status, 0, "published S3 signing vector succeeds");
chomp $output;
is($output,
   "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
   "matches AWS's published Signature V4 presigning example");

($status, $output) = run_aws({
        AWS_ACCESS_KEY_ID => "LEGACYKEY",
        AWS_SECRET_ACCESS_KEY => "legacy-secret",
    }, "--no-sanity-check", "--request", "--signature-v2", "describe-instances");
is($status, 0, "explicit legacy Signature V2 request succeeds");
like($output, qr[SignatureVersion=2], "legacy mode uses Signature V2");
unlike($output, qr[X-Amz-Algorithm], "legacy mode does not add SigV4 parameters");

done_testing();
