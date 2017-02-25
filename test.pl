#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';

open (FH, "< ./npcuser1.log");

while ( my $line = <FH>){
   if ( $line =~ /_username_/ ){
      my @l = split(/"/,$line);
      say $l[1];
    }
   if ( $line =~ /_uid_/ ){
      my @L = split(/"/,$line);
      say $L[1];
    }
}


