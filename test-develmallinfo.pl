#!/usr/bin/env perl

use strict;
use warnings;

use Devel::Mallinfo;
my $hashref = Devel::Mallinfo::mallinfo();
print "uordblks used space ", $hashref->{'uordblks'}, "\n";
 
Devel::Mallinfo::malloc_stats();  # GNU systems
