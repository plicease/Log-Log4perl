###########################################
# Test using Log::Dispatch::DBI
# Kevin Goess <cpan@goess.org>
###########################################

use Test;

use Log::Log4perl;
our $no_DBD;
use warnings;
use strict;

BEGIN {
    eval {
        require DBD::CSV;
    };
    if ($@) {
        print STDERR "DBD::CSV not installed, skipping tests\n";
        $no_DBD = 1;
        plan tests => 1;
    }else{
        plan tests => 15;
    }
}

if ($no_DBD){
    ok(1);
    exit(0);
}


require DBI;
my $dbh = DBI->connect('DBI:CSV:f_dir=t/tmp','testuser','testpw',{ PrintError => 1 });

$dbh->do('DROP TABLE log4perltest') if -e 't/tmp/log4perltest';

my $stmt = <<EOL;
    CREATE TABLE log4perltest (
      loglevel     char(9) ,   
      message   char(128),     
      shortcaller   char(5),  
      thingid    char(6),       
      category  char(16),      
      pkg    char(16),
      runtime1 char(16),
      runtime2 char(16)
      
  )
EOL

$dbh->do($stmt);

#creating a log statement where bind values 1,3,5 and 6 are 
#calculated from conversion specifiers and 2,4,7,8 are 
#calculated at runtime and fed to the $logger->whatever(...)
#statement

my $config = <<'EOT';
#log4j.category = WARN, DBAppndr, console
log4j.category = WARN, DBAppndr
log4j.appender.DBAppndr             = Log::Log4perl::Appender::DBI
log4j.appender.DBAppndr.datasource = DBI:CSV:f_dir=t/tmp
log4j.appender.DBAppndr.username  = bobjones
log4j.appender.DBAppndr.password = 12345
log4j.appender.DBAppndr.sql = \
   insert into log4perltest \
   (loglevel, message, shortcaller, thingid, category, pkg, runtime1, runtime2) \
   values (?,?,?,?,?,?,?,?)
log4j.appender.DBAppndr.params.1 = %p    
#---------------------------- #2 is message
log4j.appender.DBAppndr.params.3 = %5.5l
#---------------------------- #4 is thingid
log4j.appender.DBAppndr.params.5 = %c
log4j.appender.DBAppndr.params.6 = %C
#-----------------------------#7,8 are also runtime

log4j.appender.DBAppndr.bufferSize=2
log4j.appender.DBAppndr.warp_message=0
    
#noop layout to pass it through
log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout

#a console appender for debugging
log4j.appender.console = Log::Log4perl::Appender::Screen
log4j.appender.console.layout = Log::Log4perl::Layout::SimpleLayout


EOT

Log::Log4perl::init(\$config);


# *********************
# check a category logger

my $logger = Log::Log4perl->get_logger("groceries.beer");


#$logger->fatal('fatal message',1234,'foo','bar');
$logger->fatal('fatal message',1234,'foo',{aaa => 'aaa'});

#since we ARE buffering, that message shouldn't be there yet
{
 local $/ = undef;
 open (F, "t/tmp/log4perltest");
 my $got = <F>;
 close F;
 my $expected = <<EOL;
LOGLEVEL,MESSAGE,SHORTCALLER,THINGID,CATEGORY,PKG,RUNTIME1,RUNTIME2
EOL
  $got =~ s/[^\w ,"()]//g;  #silly DBD_CSV uses funny EOL chars
  $expected =~ s/[^\w ,"()]//g;
  ok($got, $expected);
}

$logger->warn('warning message',3456,'foo','bar');

#with buffersize == 2, now they should write
{
 local $/ = undef;
 open (F, "t/tmp/log4perltest");
 my $got = <F>;
 close F;
 my $expected = <<EOL;
LOGLEVEL,MESSAGE,SHORTCALLER,THINGID,CATEGORY,PKG,RUNTIME1,RUNTIME2
FATAL,"fatal message",main:,1234,groceries.beer,main,foo,HASH(0x84cfd64)
WARN,"warning message",main:,3456,groceries.beer,main,foo,bar
EOL
  $got =~ s/[^\w ,"()]//g;  #silly DBD_CSV uses funny EOL chars
  $expected =~ s/[^\w ,"()]//g;
  $got =~ s/HASH\(.+?\)//;
  $expected =~ s/HASH\(.+?\)//;
  ok($got, $expected);
}



$logger->debug('debug message',99,'foo','bar');

my $sth = $dbh->prepare('select * from log4perltest'); 
$sth->execute;

my $row = $sth->fetchrow_arrayref;
ok($row->[0], 'FATAL');
ok($row->[1], 'fatal message');
ok($row->[3], '1234');
ok($row->[4], 'groceries.beer');
ok($row->[5], 'main');
ok($row->[6], 'foo');
ok($row->[7], '/HASH/'); #verifying param checking for "filter=>sub{...} stuff

$row = $sth->fetchrow_arrayref;
ok($row->[0], 'WARN');
ok($row->[1], 'warning message');
ok($row->[3], '3456');
ok($row->[4], 'groceries.beer');
ok($row->[5], 'main');

#$dbh->do('DROP TABLE log4perltest');

$dbh->disconnect;

# **************************************
# checking usePreparedStmt, spurious warning bug reported by Brett Rann
# might as well give it a thorough check
Log::Log4perl->reset;

$dbh = DBI->connect('DBI:CSV:f_dir=t/tmp','testuser','testpw',{ PrintError => 1 });

$dbh->do('DROP TABLE log4perltest') if -e 't/tmp/log4perltest';

$stmt = <<EOL;
    CREATE TABLE log4perltest (
      loglevel     char(9) ,   
      message   char(128),     
      
  )
EOL

$dbh->do($stmt);


$config = <<'EOT';
#log4j.category = WARN, DBAppndr, console
log4j.category = WARN, DBAppndr
log4j.appender.DBAppndr             = Log::Log4perl::Appender::DBI
log4j.appender.DBAppndr.datasource = DBI:CSV:f_dir=t/tmp
log4j.appender.DBAppndr.sql = \
   insert into log4perltest \
   (loglevel, message) \
   values (?,?)
log4j.appender.DBAppndr.params.1 = %p    
#---------------------------- #2 is message

log4j.appender.DBAppndr.usePreparedStmt=2
log4j.appender.DBAppndr.warp_message=0
    
#noop layout to pass it through
log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout

EOT

Log::Log4perl::init(\$config);

$logger = Log::Log4perl->get_logger("groceries.beer");

$logger->fatal('warning message');

#since we're not buffering, this message should show up immediately
{
 local $/ = undef;
 open (F, "t/tmp/log4perltest");
 my $got = <F>;
 close F;
 my $expected = <<EOL;
LOGLEVEL,MESSAGE
FATAL,"warning message"
EOL
  $got =~ s/[^\w ,"()]//g;  #silly DBD_CSV uses funny EOL chars
  $expected =~ s/[^\w ,"()]//g;
  ok($got, $expected);
}

$logger->fatal('warning message');

