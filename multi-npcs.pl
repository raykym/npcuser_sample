#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

#if ($#ARGV == -1) {
#     say "Usage: multi_npcs.pl";
#     exit;
#     }

system('/home/debian/perlwork/work/Walkworld/npcuser1.pl > /dev/null 2>&1 &');
system('/home/debian/perlwork/work/Walkworld/npcuser2.pl > /dev/null 2>&1 &');
system('/home/debian/perlwork/work/Walkworld/npcuser3.pl > /dev/null 2>&1 &');
system('/home/debian/perlwork/work/Walkworld/npcuser4.pl > /dev/null 2>&1 &');
system('/home/debian/perlwork/work/Walkworld/npcuser5.pl > /dev/null 2>&1 &');
system('/home/debian/perlwork/work/Walkworld/npcuser6.pl > /dev/null 2>&1 &');
