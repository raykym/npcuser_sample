#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Data::Dumper;

# 引数を受けて、周囲に配置する
# multi-ghost.pl [lat] [lng]

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
         { "email" => 'npcuser1@test.com' , "emailpass" => "npcuser1_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser2@test.com' , "emailpass" => "npcuser2_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser3@test.com' , "emailpass" => "npcuser3_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser4@test.com' , "emailpass" => "npcuser4_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser5@test.com' , "emailpass" => "npcuser5_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser6@test.com' , "emailpass" => "npcuser6_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser7@test.com' , "emailpass" => "npcuser7_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser8@test.com' , "emailpass" => "npcuser8_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser9@test.com' , "emailpass" => "npcuser9_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser10@test.com' , "emailpass" => "npcuser10_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
        { "email" => 'npcuser11@test.com' , "emailpass" => "npcuser11_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser12@test.com' , "emailpass" => "npcuser12_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser13@test.com' , "emailpass" => "npcuser13_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser14@test.com' , "emailpass" => "npcuser14_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser15@test.com' , "emailpass" => "npcuser15_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser16@test.com' , "emailpass" => "npcuser16_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser17@test.com' , "emailpass" => "npcuser17_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser18@test.com' , "emailpass" => "npcuser18_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser19@test.com' , "emailpass" => "npcuser19_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser20@test.com' , "emailpass" => "npcuser20_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser21@test.com' , "emailpass" => "npcuser21_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser22@test.com' , "emailpass" => "npcuser22_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser23@test.com' , "emailpass" => "npcuser23_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser24@test.com' , "emailpass" => "npcuser24_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser25@test.com' , "emailpass" => "npcuser25_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser26@test.com' , "emailpass" => "npcuser26_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser27@test.com' , "emailpass" => "npcuser27_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser28@test.com' , "emailpass" => "npcuser28_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser29@test.com' , "emailpass" => "npcuser29_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser30@test.com' , "emailpass" => "npcuser30_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser31@test.com' , "emailpass" => "npcuser31_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser32@test.com' , "emailpass" => "npcuser32_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser33@test.com' , "emailpass" => "npcuser33_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser34@test.com' , "emailpass" => "npcuser34_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser35@test.com' , "emailpass" => "npcuser35_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser36@test.com' , "emailpass" => "npcuser36_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser37@test.com' , "emailpass" => "npcuser37_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser38@test.com' , "emailpass" => "npcuser38_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser39@test.com' , "emailpass" => "npcuser39_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser40@test.com' , "emailpass" => "npcuser40_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser41@test.com' , "emailpass" => "npcuser41_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser42@test.com' , "emailpass" => "npcuser42_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser43@test.com' , "emailpass" => "npcuser43_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser44@test.com' , "emailpass" => "npcuser44_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser45@test.com' , "emailpass" => "npcuser45_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser46@test.com' , "emailpass" => "npcuser46_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser47@test.com' , "emailpass" => "npcuser47_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser48@test.com' , "emailpass" => "npcuser48_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser49@test.com' , "emailpass" => "npcuser49_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
         { "email" => 'npcuser50@test.com' , "emailpass" => "npcuser50_pass" , "lat" => rand_lat($ARGV[0]) , "lng" => rand_lng($ARGV[1]) , "runmode" => "random"},
          ];


system('echo "" > ./multi-ghost.log');

foreach my $in (@$npclist){
   #    print Dumper($in);

 #  system("./npcuser_n.pl $in->{email} $in->{emailpass} $in->{lat} $in->{lng} $in->{runmode} >> ./multi-ghost.log 2>&1 &");
   system("./npcuser_n_site.pl $in->{email} $in->{emailpass} $in->{lat} $in->{lng} $in->{runmode} >> ./multi-ghost.log 2>&1 &");
   sleep 1;
}
