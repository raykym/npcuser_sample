#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Data::Dumper;

my $npclist = [
         { "email" => 'npcuser1@test.com' , "emailpass" => "npcuser1_pass" , "lat" => 35.67658 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser2@test.com' , "emailpass" => "npcuser2_pass" , "lat" => 35.68658 , "lng" => 139.92635 , "runmode" => "random"},
         { "email" => 'npcuser3@test.com' , "emailpass" => "npcuser3_pass" , "lat" => 35.68958 , "lng" => 139.91035 , "runmode" => "random"},
         { "email" => 'npcuser4@test.com' , "emailpass" => "npcuser4_pass" , "lat" => 35.67658 , "lng" => 139.93635 , "runmode" => "random"},
         { "email" => 'npcuser5@test.com' , "emailpass" => "npcuser5_pass" , "lat" => 35.68158 , "lng" => 139.91535 , "runmode" => "random"},
         { "email" => 'npcuser6@test.com' , "emailpass" => "npcuser6_pass" , "lat" => 35.69658 , "lng" => 139.91735 , "runmode" => "random"},
         { "email" => 'npcuser7@test.com' , "emailpass" => "npcuser7_pass" , "lat" => 35.67658 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser8@test.com' , "emailpass" => "npcuser8_pass" , "lat" => 35.68358 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser9@test.com' , "emailpass" => "npcuser9_pass" , "lat" => 35.69658 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser10@test.com' , "emailpass" => "npcuser10_pass" , "lat" => 35.68658 , "lng" => 139.91135 , "runmode" => "random"},
         { "email" => 'npcuser11@test.com' , "emailpass" => "npcuser11_pass" , "lat" => 35.68658 , "lng" => 139.91235 , "runmode" => "random"},
         { "email" => 'npcuser12@test.com' , "emailpass" => "npcuser12_pass" , "lat" => 35.68658 , "lng" => 139.91335 , "runmode" => "random"},
         { "email" => 'npcuser13@test.com' , "emailpass" => "npcuser13_pass" , "lat" => 35.67658 , "lng" => 139.91435 , "runmode" => "random"},
         { "email" => 'npcuser14@test.com' , "emailpass" => "npcuser14_pass" , "lat" => 35.68658 , "lng" => 139.92535 , "runmode" => "random"},
         { "email" => 'npcuser15@test.com' , "emailpass" => "npcuser15_pass" , "lat" => 35.66658 , "lng" => 139.92635 , "runmode" => "random"},
         { "email" => 'npcuser16@test.com' , "emailpass" => "npcuser16_pass" , "lat" => 35.68658 , "lng" => 139.92635 , "runmode" => "random"},
         { "email" => 'npcuser17@test.com' , "emailpass" => "npcuser17_pass" , "lat" => 35.67658 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser18@test.com' , "emailpass" => "npcuser18_pass" , "lat" => 35.68358 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser19@test.com' , "emailpass" => "npcuser19_pass" , "lat" => 35.68258 , "lng" => 139.90635 , "runmode" => "random"},
         { "email" => 'npcuser20@test.com' , "emailpass" => "npcuser20_pass" , "lat" => 35.68758 , "lng" => 139.91635 , "runmode" => "random"},
          ];

foreach my $in (@$npclist){
   #    print Dumper($in);

   system("./npcuser_f.pl $in->{email} $in->{emailpass} $in->{lat} $in->{lng} $in->{runmode} > /dev/null 2>&1 &");

}
