#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use Devel::Size qw(size total_size);
 
#my $size = size("A string");
#my @foo = (1, 2, 3, 4, 5);
#my $other_size = size(\@foo);
#my $foo = {a => [1, 2, 3],
#    b => {a => [1, 3, 4]}
#       };
#my $total_size = total_size($foo);

use Mojo::UserAgent;

my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);


my $size = size($ua);
my $total_size = total_size($ua);

say "size: $size | total: $total_size";
