#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Data::Dumper;

# 引数を受けて、周囲に配置する
# multi-loginloop.pl [lat] [lng]

$| = 1;

if ( $#ARGV < 1 ) { exit; }

sub rand_lat {
   my $b_lat = shift;

   my $lat = $ARGV[0] + rand(0.02) - rand(0.02);

   return $lat;
}

sub rand_lng {
    my $b_lng = shift;

    my $lng = $ARGV[1] + rand(0.02) - rand(0.02);

   return $lng;
}

my $npclist = [
         { "email" => 'searchnpc1@test.com' , "emailpass" => "searchnpc1_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc2@test.com' , "emailpass" => "searchnpc2_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc3@test.com' , "emailpass" => "searchnpc3_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc4@test.com' , "emailpass" => "searchnpc4_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc5@test.com' , "emailpass" => "searchnpc5_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc6@test.com' , "emailpass" => "searchnpc6_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc7@test.com' , "emailpass" => "searchnpc7_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc8@test.com' , "emailpass" => "searchnpc8_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc9@test.com' , "emailpass" => "searchnpc9_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc10@test.com' , "emailpass" => "searchnpc10_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
        { "email" => 'searchnpc11@test.com' , "emailpass" => "searchnpc11_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc12@test.com' , "emailpass" => "searchnpc12_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc13@test.com' , "emailpass" => "searchnpc13_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc14@test.com' , "emailpass" => "searchnpc14_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc15@test.com' , "emailpass" => "searchnpc15_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc16@test.com' , "emailpass" => "searchnpc16_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc17@test.com' , "emailpass" => "searchnpc17_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc18@test.com' , "emailpass" => "searchnpc18_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc19@test.com' , "emailpass" => "searchnpc19_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc20@test.com' , "emailpass" => "searchnpc20_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc21@test.com' , "emailpass" => "searchnpc21_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc22@test.com' , "emailpass" => "searchnpc22_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc23@test.com' , "emailpass" => "searchnpc23_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc24@test.com' , "emailpass" => "searchnpc24_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc25@test.com' , "emailpass" => "searchnpc25_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc26@test.com' , "emailpass" => "searchnpc26_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc27@test.com' , "emailpass" => "searchnpc27_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc28@test.com' , "emailpass" => "searchnpc28_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc29@test.com' , "emailpass" => "searchnpc29_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc30@test.com' , "emailpass" => "searchnpc30_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc31@test.com' , "emailpass" => "searchnpc31_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc32@test.com' , "emailpass" => "searchnpc32_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc33@test.com' , "emailpass" => "searchnpc33_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc34@test.com' , "emailpass" => "searchnpc34_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc35@test.com' , "emailpass" => "searchnpc35_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc36@test.com' , "emailpass" => "searchnpc36_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc37@test.com' , "emailpass" => "searchnpc37_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc38@test.com' , "emailpass" => "searchnpc38_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc39@test.com' , "emailpass" => "searchnpc39_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc40@test.com' , "emailpass" => "searchnpc40_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc41@test.com' , "emailpass" => "searchnpc41_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc42@test.com' , "emailpass" => "searchnpc42_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc43@test.com' , "emailpass" => "searchnpc43_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc44@test.com' , "emailpass" => "searchnpc44_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc45@test.com' , "emailpass" => "searchnpc45_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc46@test.com' , "emailpass" => "searchnpc46_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc47@test.com' , "emailpass" => "searchnpc47_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc48@test.com' , "emailpass" => "searchnpc48_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc49@test.com' , "emailpass" => "searchnpc49_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'searchnpc50@test.com' , "emailpass" => "searchnpc50_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
          ];


system('echo "" > ./multi-loginloop.log');

foreach my $in (@$npclist){
   #    print Dumper($in);

   system("./loginuser.pl $in->{email} $in->{emailpass} $in->{lat} $in->{lng} $in->{runmode} >> ./multi-loginloop.log 2>&1 &");

   sleep 1;
}


#for ( my $count=0; $count < 10 ; $count++) {
#   system("./loginuser.pl $npclist->[$count]->{email} $npclist->[$count]->{emailpass} $npclist->[$count]->{lat} $npclist->[$count]->{lng} $npclist->[$count]->{runmode} >> ./multi-loginloop.log 2>&1 &");
#   sleep 1;
#}




