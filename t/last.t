use Cron::Toolkit;
use Time::Moment;

my $c = Cron::Toolkit->new(expression => '0 0 0 L-2 * ? *');
my $tm = Time::Moment->new(2025, 1, 29);  # Jan has 31 days
ok($c->_is_match($tm), "L-2 matches 29th in Jan");
