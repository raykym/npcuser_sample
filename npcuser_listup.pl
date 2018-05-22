#!/usr/bin/env perl

# npcuser_list.pl   redisからnpcuser_n_sitedb_w.pl用のGACCエントリーを呼び出してリストアップする

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::Redis2;
use Mojo::JSON qw( from_json to_json );

my $redis ||= Mojo::Redis2->new(url => 'redis://10.140.0.8:6379');

my $gacckeylist = $redis->keys("GACC*");

my @gacclists = ();

for my $i (@$gacckeylist){

    my $gaccp = from_json( $redis->get("$i") );

    push (@gacclists,$gaccp);   # 2次元配列

}

for my $i (@gacclists){

    for my $j (@$i){
        say "$j->{name} $j->{userid} LIFECOUNT: $j->{lifecount} STATUS: $j->{status} SPN: $j->{point_spn} RUNDIRECT: $j->{rundirect} TARGET: $j->{target} PLACE: $j->{place}->{name}";

    }  # for $j

}
