#!/usr/bin/env perl

# ghostmanidを引数で得て、リストを表示する

# ghostmanid_getlist.pl [ghostmanid]

use strict;
use warnings;
use utf8;
use feature 'say';

use Mojo::Redis2;
use Mojo::JSON qw(encode_json decode_json from_json to_json);

$| = 1;

my $ghostmanid = $ARGV[0];
   if ( ! defined $ghostmanid ) {
        say "UNDEFINED ghostmanid!!!!!!!";
        exit;
       }

my $redis ||= Mojo::Redis2->new( url => 'redis://10.140.0.4:6379');

my $gacclist = $redis->get("GACC$ghostmanid");
    if ( defined $gacclist) {
        $gacclist = from_json($gacclist);
        } else {
               @$gacclist = ();
        }

my @list = @$gacclist;

foreach my $line (@$gacclist){

    say "$line->{name} $line->{status} $line->{target} $line->{lifecount} $line->{point_spn}";

}

say "count: $#list + 1";
