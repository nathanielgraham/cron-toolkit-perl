#!/usr/bin/env perl
# t/20-new_from_crontab.t
use strict;
use warnings;
use Test::More;
use lib 'lib';
use Cron::Toolkit;

plan tests => 17;

my $crontab = <<'END_CRONTAB';
# Comment line
MAILTO=admin@example.com
PATH=/usr/local/bin:/usr/bin:/bin

# Simple Unix entry
* * * * * /bin/echo "every minute"

# With user
0 2 * * * backupuser /usr/local/bin/full-backup

# Quartz entry
0 0 12 ? * MON-FRI * /usr/bin/daily-report

# Alias
@hourly root /scripts/hourly-job.sh

# Env vars + entry
FOO=bar
0 5 * * * /script --foo=$FOO

# Trailing comment
30 14 * * * /lunch-reminder # do not forget!
END_CRONTAB

my @entries = Cron::Toolkit->new_from_crontab($crontab);

is(scalar @entries, 6, "6 valid entries parsed");

# 1. Simple Unix
is($entries[0]->as_string, "0 * * * * ? *", "simple Unix normalized");
is($entries[0]->command, "/bin/echo \"every minute\"", "command preserved");
is($entries[0]->user, undef, "no user");
is_deeply($entries[0]->env, {}, "no env");

# 2. With user
is($entries[1]->as_string, "0 0 2 * * ? *", "backup entry");
is($entries[1]->user, "backupuser", "user parsed");
is($entries[1]->command, "/usr/local/bin/full-backup", "command");

# 3. Quartz entry
is($entries[2]->as_string, "0 0 12 ? * MON-FRI *", "Quartz MON-FRI preserved");
is($entries[2]->command, "/usr/bin/daily-report", "Quartz command");

# 4. Alias
is($entries[3]->as_string, "0 0 * * * ? *", '@hourly expanded correctly');
is($entries[3]->user, "root", "alias with user");
is($entries[3]->command, "/scripts/hourly-job.sh", "alias command");

# 5. Env var inheritance
is($entries[4]->env->{FOO}, "bar", "env var inherited");
is($entries[4]->command, "/script --foo=bar", "env var expanded in command");

# 6. Trailing comment ignored
is($entries[5]->command, "/lunch-reminder", "trailing comment stripped");

# Global env (MAILTO, PATH) are NOT attached to individual entries
ok(!exists $entries[0]->env->{MAILTO}, "global vars not attached to entries");

# Error cases
my $bad = "* * * * * * * extra-field\n";
eval { Cron::Toolkit->new_from_crontab($bad) };
like($@, qr/expected 5-7 fields/, "too many fields dies");

my $bad2 = "L * * * * command\n";
eval { Cron::Toolkit->new_from_crontab($bad2) };
like($@, qr/L only allowed in dom or dow/, "L in minute dies");

done_testing;
